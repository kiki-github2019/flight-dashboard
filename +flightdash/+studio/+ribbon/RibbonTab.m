classdef RibbonTab < handle
    %RIBBONTAB  One ribbon tab — title + horizontal RibbonGroup row.

    properties (Access = public)
        Title   char = ''
        Groups  cell = {}    % cell of RibbonGroup handles
    end

    properties (Access = public, Transient)
        Tab               % uitab
        GroupGrid         % uigridlayout
    end

    methods
        function obj = RibbonTab(title, groups)
            obj.Title = char(title);
            if nargin >= 2 && iscell(groups)
                obj.Groups = groups;
            end
        end

        function add(obj, group)
            obj.Groups{end+1} = group;
        end

        function build(obj, parentTabGroup, adapter)
            obj.Tab = uitab(parentTabGroup, 'Title', obj.Title);
            % Layout: groups in a horizontal flow + a final flex spacer.
            nGroups = numel(obj.Groups);
            cols = repmat({'fit'}, 1, nGroups);
            cols{end+1} = '1x'; %#ok<AGROW> trailing spacer eats slack
            obj.GroupGrid = uigridlayout(obj.Tab, [1 nGroups + 1]);
            obj.GroupGrid.RowHeight     = {'1x'};
            obj.GroupGrid.ColumnWidth   = cols;
            obj.GroupGrid.ColumnSpacing = 4;
            obj.GroupGrid.Padding       = [4 2 4 2];
            obj.GroupGrid.BackgroundColor = [0.94 0.94 0.94];

            for k = 1:numel(obj.Groups)
                g = obj.Groups{k};
                if isempty(g) || ~isvalid(g), continue; end
                g.build(obj.GroupGrid, adapter);
            end
            % Spacer cell — invisible.
            uipanel(obj.GroupGrid, 'BorderType', 'none', ...
                'BackgroundColor', [0.94 0.94 0.94]);
        end

        function delete(obj)
            for k = 1:numel(obj.Groups)
                try
                    g = obj.Groups{k};
                    if ~isempty(g) && isvalid(g), delete(g); end
                catch
                end
            end
            obj.Groups = {};
            try, if ~isempty(obj.Tab) && isvalid(obj.Tab), delete(obj.Tab); end, catch, end
        end
    end
end
