function [Data, Info, SW] = swa_FindSWRef(Data, Info, SW)

% Check for appropriate parameters
if ~isfield(Info.Parameters, 'Ref_Method')
    fprintf(1, 'Error: No detection parameters found in the ''Info'' structure');
    return;
end

% Initialise the SW Structure
if nargin < 3 || isempty(SW)
    SW = struct(...
        'Ref_Region',           [], ...     % region the wave was found in
        'Ref_DownInd',          [], ...     % index of downward zero crossing or previous maxima if using MNP
        'Ref_PeakInd',          [], ...     % index of maximum negativity
        'Ref_UpInd',            [], ...     % index of upward zero crossing or subsequent maxima
        'Ref_PeakAmp',          [], ...     % negative peak amplitude
        'Ref_P2PAmp',           [], ...     % only used as a criteria for the non-envelope references
        'Ref_NegSlope',         [], ...     % maximum of negative slope
        'Ref_PosSlope',         [], ...     % maximum of slope index in the upswing
        'Channels_Active',      [], ...     % List of channels with a slow wave, in temporal order
        'Channels_NegAmp',      [], ...     % Peak negative amplitude in the channels
        'Channels_NegAmpInd',   [], ...     % Channel index for the peak negative amplitude
        'Channels_Globality',   [], ...     % Percentage of active channels from total
        'Travelling_Delays',    [], ...     % Delay of negative peak for each channel in samples
        'Travelling_DelayMap',  [], ...     % Interpolated map of the delays
        'Travelling_Streams',   [], ...     % Principle direction of travel
        'Code',                 []);        % Code for the wave (type 1 or type 2)

    OSWCount = 0; % counts empty as one... fix!
    SWCount  = 0;
else
    OSWCount = length(SW); % counts empty as one... fix!
    SWCount  = length(SW);
end

% loop for each reference
for refWave = 1:size(Data.SWRef,1)

    switch Info.Parameters.Ref_ZCorMNP

        case 'MNP'
            % Peak detection method
            % ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            % Get Downward and Upward Zero Crossings (DZC and UZC)
            slopeData   = [0 diff(Data.SWRef(refWave,:))];   % gives the differential of data (slope)
            % Calculate xth percentile slope
            x = sort(slopeData);
            slopeThresh = x(round(length(x)*Info.Parameters.Ref_SlopeMin));
            % Find all the negative peaks
            MNP  = find(diff(sign(slopeData))==2);
            % Find all the positive peaks
            MPP  = find(diff(sign(slopeData))==-2);

            % Check for earlier MPP than MNP
            if MNP(1) < MPP(1)
                MNP(1) = [];
            end
            % Check that last MNP has a later MPP
            if MNP(end) > MPP(end)
                MNP(end)=[];
            end

            % calculate amplitude threshold criteria (before eliminating short waves)
            if ~isempty(Info.Parameters.Ref_AmpStd)
                StdMor = mad(Data.SWRef(refWave, MNP), 1); % Returns the absolute deviation from the median (to avoid outliers)
                Info.Parameters.Ref_NegAmpMin = (StdMor*Info.Parameters.Ref_AmpStd)+abs(median(Data.SWRef(MNP))); % Overwrite amp threshold
            end

            % iteratively erase small notches
            nb = 1;
            while nb > 0;
                posBumps = MPP(2:end)-MNP < Info.Parameters.Ref_WaveLength(1)*Info.Recording.sRate/10;
                MPP([false, posBumps]) = [];
                MNP(posBumps)     = [];

                negBumps = MNP-MPP(1:end-1) < Info.Parameters.Ref_WaveLength(1)*Info.Recording.sRate/10;
                MPP(negBumps) = [];
                MNP(negBumps) = [];

                nb = max(sum(posBumps), sum(negBumps));
            end

            % Define badWaves
            badWaves = false(1, length(MNP));

            % Wavelength criteria
            % ```````````````````
            % MPP->MPP length
            MPP2MPPlength = diff(MPP);
            badWaves    ( MPP2MPPlength < Info.Parameters.Ref_WaveLength(1)*Info.Recording.sRate...
                        | MPP2MPPlength > Info.Parameters.Ref_WaveLength(2)*Info.Recording.sRate)...
                        = true;
            % MNP->MPP length
            % must be at least half of the specified wavelength
            MNP2MPPlength = MPP(2:end)-MNP;
            badWaves    ( MNP2MPPlength < Info.Parameters.Ref_WaveLength(1)*Info.Recording.sRate/2 ...
                        | MNP2MPPlength > Info.Parameters.Ref_WaveLength(2)*Info.Recording.sRate/2) ...
                        = true;

            % Amplitude criteria
            % ```````````````````
            % mark lower than threshold amps and larger than 200uV (artifacts)
            badWaves    ( Data.SWRef(refWave, MNP) > -Info.Parameters.Ref_NegAmpMin...
                | Data.SWRef(refWave, MNP) < -200)...
                = true;

            % peak to peak amplitude
            p2p = Data.SWRef(MPP(2:end))-Data.SWRef(MNP);
            % peaks should not be calculated for envelope references
            if ~strcmp(Info.Parameters.Ref_Method, 'Envelope')
                badWaves ( p2p < Info.Parameters.Ref_Peak2Peak)...
                    = true;
            end

            % Get all the MNP from a previous reference
            % this will return empty for the first reference
            AllPeaks = [SW.Ref_PeakInd];
            
            % Loop through each MNP to save criteria
            for n = find(~badWaves)
                
                % Check if the SW has already been found in another reference channel
                if refWave > 1
                    [c, SWid] = max(double(AllPeaks > MPP(n)) + double(AllPeaks < MPP(n+1)));
                    if c == 2
                        % Check which region has the bigger P2P wave...
                        if Data.SWRef(MNP(n)) < SW(SWid).Ref_PeakAmp
                            % If the new region does then overwrite previous data with larger reference
                            SW(SWid).Ref_Region    = [refWave, SW(SWid).Ref_Region];
                            SW(SWid).Ref_DownInd   = MPP(n);
                            SW(SWid).Ref_PeakInd   = MNP(n);
                            SW(SWid).Ref_UpInd     = MPP(n+1);
                            SW(SWid).Ref_PeakAmp   = Data.SWRef(MNP(n));
                            SW(SWid).Ref_P2PAmp    = p2p(n);
                            SW(SWid).Ref_NegSlope  = min(slopeData(1,MPP(n):MPP(n+1)));
                            SW(SWid).Ref_PosSlope  = max(slopeData(1,MPP(n):MPP(n+1)));
                        else
                            % Just add the reference region
                            SW(SWid).Ref_Region(end+1) = refWave;
                        end
                        
                        continue;
                    end
                end
                
                % Keep count of the waves found
                SWCount = SWCount+1;
                
                % Save the values
                SW(SWCount).Ref_Region    = refWave;
                SW(SWCount).Ref_DownInd   = MPP(n);                
                SW(SWCount).Ref_PeakInd    = MNP(n);
                SW(SWCount).Ref_UpInd     = MPP(n+1);
                SW(SWCount).Ref_PeakAmp   = Data.SWRef(MNP(n));
                SW(SWCount).Ref_P2PAmp = p2p(n);
                SW(SWCount).Ref_NegSlope  = min(slopeData(1,MPP(n):MPP(n+1)));
                SW(SWCount).Ref_PosSlope  = max(slopeData(1,MPP(n):MPP(n+1)));
                
            end
            
        % Zero crossing detection method
        % ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        case 'ZC'
            
            % Get Downward and Upward Zero Crossings (DZC and UZC)
            signData    = sign(Data.SWRef(refWave,:));       % gives the sign of data
            slopeData   = [0 diff(Data.SWRef(refWave,:))];   % gives the differential of data (slope)
            
            % Calculate xth percentile slope
            x = sort(slopeData);
            slopeThresh = x(round(length(x)*Info.Parameters.Ref_SlopeMin));
            
            DZC = find(diff(signData) == -2); % -2 indicates when the sign goes from 1 to -1
            UZC = find(diff(signData) == 2);
            
            % Check for earlier initial UZC than DZC
            if DZC(1)>UZC(1)
                UZC(1)=[];
                % in case the last DZC does not have a corresponding UZC then delete it
                if length(DZC) ~= length(UZC)
                    DZC(end)=[];
                end
            end
            
            % Check for last DZC with no UZC
            if length(DZC)>length(UZC)
                DZC(end) = [];
            end
            
            % calculate amplitude threshold criteria
            % do not calculate if the AmpStd has been left empty
            if ~isempty(Info.Parameters.Ref_AmpStd)
                % Maximum Negative Point (trough of the wave)
                MNP  = find(diff(sign(slopeData))==2);  
                % Return the absolute deviation from the median (to avoid outliers)
                StdMor = mad(Data.SWRef(MNP), 1);
                % Set the new amplitude threshold in the Info structure and potentially overwrite the old settings
                Info.Parameters.Ref_NegAmpMin = (StdMor*Info.Parameters.Ref_AmpStd)+abs(mean(Data.SWRef(MNP)));
            end
            
            % Test Wavelength
            % ```````````````
            % Get all the wavelengths
            SWLengths = UZC-DZC;
            % Too short
            BadZC = SWLengths < Info.Parameters.Ref_WaveLength(1)*Info.Recording.sRate;
            % Too long
            BadZC(  SWLengths > Info.Parameters.Ref_WaveLength(2)*Info.Recording.sRate) = true;
            % Eliminate the indices
            UZC(BadZC) = [];
            DZC(BadZC) = [];

            % To check differences between next peaks found...
            AllPeaks = [SW.Ref_PeakInd];
            
            % Loop through each DZC for criteria
            for n = 1:length(DZC)
                
                % Test for negative amplitude
                [NegPeakAmp,NegPeakId] = min(Data.SWRef(1,DZC(n):UZC(n)));
                if abs(NegPeakAmp) < Info.Parameters.Ref_NegAmpMin
                    continue;
                end
                NegPeakId = NegPeakId+DZC(n);
                
                % MDC Test for peak to peak amplitude
                PosPeakAmp = max(Data.SWRef(1,UZC(n):UZC(n)+2*Info.Recording.sRate));
                if strcmp(Info.Parameters.Ref_Method,'MDC')
                    if PosPeakAmp-NegPeakAmp < Info.Parameters.Ref_Peak2Peak
                        continue;
                    end
                end
                
                % Test for positive slope
                MaxPosSlope = max(slopeData(1,DZC(n):UZC(n)));
                if MaxPosSlope < slopeThresh
                    continue;
                end
                
                % Check if the SW has already been found in another reference channel
                if refWave > 1
                    [c, SWid] = max(double(AllPeaks > DZC(n)) + double(AllPeaks < UZC(n)));
                    if c == 2
                        % Check which region has the bigger P2P wave...
                        if Data.SWRef(NegPeakId) < SW(SWid).Ref_PeakAmp
                            % If the new region does then overwrite previous data with larger reference
                            SW(SWid).Ref_Region    = [refWave, SW(SWid).Ref_Region];
                            SW(SWid).Ref_DownInd   = DZC(n);
                            SW(SWid).Ref_PeakInd   = NegPeakId;
                            SW(SWid).Ref_UpInd     = UZC(n);
                            SW(SWid).Ref_PeakAmp   = Data.SWRef(NegPeakId);
                            SW(SWid).Ref_P2PAmp    = PosPeakAmp-NegPeakAmp;
                            SW(SWid).Ref_NegSlope  = min(slopeData(1,DZC(n):UZC(n)));
                            SW(SWid).Ref_PosSlope  = MaxPosSlope;
                            
                        else
                            % Just add the reference region
                            SW(SWid).Ref_Region(end+1) = refWave;
                            
                        end
                        
                        continue;
                    end
                end
                
                % Keep count of the waves found
                SWCount = SWCount+1;
                
                % Save the values
                SW(SWCount).Ref_Region    = refWave;
                SW(SWCount).Ref_DownInd   = DZC(n);                
                SW(SWCount).Ref_PeakInd   = NegPeakId;
                SW(SWCount).Ref_UpInd     = UZC(n);
                SW(SWCount).Ref_PeakAmp   = Data.SWRef(NegPeakId);
                SW(SWCount).Ref_P2PAmp    = PosPeakAmp-NegPeakAmp;
                SW(SWCount).Ref_NegSlope  = min(slopeData(1,DZC(n):UZC(n)));
                SW(SWCount).Ref_PosSlope  = MaxPosSlope;
                               
            end
            
        otherwise
            fprintf(1, 'Error: Unrecognised detection method');
            return;
    end
    
    if nargin == 3
        fprintf(1, 'Information: %d slow waves added to structure \n', length(SW)-OSWCount);
    else
        fprintf(1, 'Information: %d slow waves found in data series \n', length(SW)-OSWCount);
    end
    
end
