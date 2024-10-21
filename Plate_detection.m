function noPlate = Plate_detection(imagePath)

    % Kiểm tra xem đường dẫn ảnh có được cung cấp không
    if nargin < 1 || isempty(imagePath)
        disp('Bạn cần cung cấp đường dẫn ảnh!');
        return;
    end

    % Đọc và tiền xử lý ảnh
    im1 = imread(imagePath);
    imgray = rgb2gray(im1);

    % Nhị phân hóa ảnh
    imbin = imbinarize(imgray);

    % Phát hiện cạnh
    im = edge(imgray, 'prewitt');

    % Tìm vùng biển số
    Iprops1 = regionprops(im, 'BoundingBox', 'Area', 'Image');
    [boundingBox1] = findLargestArea(Iprops1);

    imwrite(imcrop(imread(imagePath), boundingBox1), fullfile(tempdir, 'cropped_plate.png'));

    % Cắt vùng biển số
    im = imcrop(imbin, boundingBox1);

    % Loại bỏ nhiễu
    im = bwareaopen(~im, 500);
    [h, w] = size(im);

    % Tách và nhận dạng từng ký tự
    Iprops = regionprops(im, 'BoundingBox', 'Area', 'Image', 'Centroid');
    [noPlate, charImages] = recognizeCharactersWithVisualization(Iprops, h, w);

    % Tạo hình ảnh visualization
    visImage = createVisualization(im, charImages);
    
    % Lưu hình ảnh visualization
    imwrite(visImage, fullfile(tempdir, 'char_visualization.png'));
end

function visImage = createVisualization(im, charImages)
    % Tính toán kích thước cho hình ảnh kết quả
    maxCharHeight = max(cellfun(@(x) size(x, 1), charImages));
    maxCharWidth = max(cellfun(@(x) size(x, 2), charImages));
    numChars = length(charImages);
    
    % Tạo hình ảnh nền trắng
    padding = 20;
    visHeight = size(im, 1) + maxCharHeight + 3*padding;
    visWidth = max(size(im, 2), numChars * (maxCharWidth + padding) + padding);
    visImage = ones(visHeight, visWidth) * 255;
    
    % Vẽ hình ảnh gốc
    startY = padding;
    startX = round((visWidth - size(im, 2)) / 2);  % Căn giữa hình ảnh gốc
    visImage(startY:startY+size(im,1)-1, startX:startX+size(im,2)-1) = im * 255;
    
    % Thêm các ký tự đã nhận dạng
    startY = size(im, 1) + 2*padding;
    startX = padding;
    for i = 1:numChars
        charImg = charImages{i};
        [charHeight, charWidth] = size(charImg);
        
        % Tính toán vị trí để căn giữa ký tự trong ô của nó
        charStartY = startY + round((maxCharHeight - charHeight) / 2);
        charStartX = startX + round((maxCharWidth - charWidth) / 2);
        
        % Đặt ký tự vào hình ảnh kết quả
        visImage(charStartY:charStartY+charHeight-1, charStartX:charStartX+charWidth-1) = charImg * 255;
        
        % Vẽ đường viền xung quanh ký tự
        visImage(startY:startY+maxCharHeight-1, startX:startX+maxCharWidth-1) = ...
            drawBorder(visImage(startY:startY+maxCharHeight-1, startX:startX+maxCharWidth-1));
        
        % Di chuyển đến ô tiếp theo
        startX = startX + maxCharWidth + padding;
    end
    
    % Chuyển đổi sang uint8
    visImage = uint8(visImage);
end

function borderedImage = drawBorder(image)
    borderWidth = 2;
    [height, width] = size(image);
    borderedImage = image;
    
    % Vẽ viền trên và dưới
    borderedImage(1:borderWidth, :) = 0;
    borderedImage(end-borderWidth+1:end, :) = 0;
    
    % Vẽ viền trái và phải
    borderedImage(:, 1:borderWidth) = 0;
    borderedImage(:, end-borderWidth+1:end) = 0;
end

function [noPlate, charImages] = recognizeCharactersWithVisualization(Iprops, height, width)
    count = numel(Iprops);
    noPlate = '';
    charImages = {};

    % Lấy thông tin về vị trí và kích thước của tất cả ký tự
    charInfo = [];
    for i = 1:count
        bbox = Iprops(i).BoundingBox;
        centroid = Iprops(i).Centroid;
        ow = size(Iprops(i).Image, 2);
        oh = size(Iprops(i).Image, 1);

        if ow < (height/2) && oh > (height/3)
            charInfo = [charInfo; i centroid bbox];
            charImages{end+1} = Iprops(i).Image;
        end
    end

    if isempty(charInfo)
        return;
    end

    % Xác định loại biển số và xử lý
    yCoords = charInfo(:, 3);
    yDiff = max(yCoords) - min(yCoords);

    if yDiff > height/4
        % Xử lý biển 2 hàng
        yThreshold = (max(yCoords) + min(yCoords)) / 2;
        topChars = charInfo(yCoords <= yThreshold, :);
        bottomChars = charInfo(yCoords > yThreshold, :);

        [~, topOrder] = sort(topChars(:, 2));
        [~, bottomOrder] = sort(bottomChars(:, 2));

        % Đọc hàng trên
        for i = 1:size(topChars, 1)
            idx = topChars(topOrder(i), 1);
            letter = Letter_detection(Iprops(idx).Image);
            noPlate = [noPlate letter];
        end

        noPlate = [noPlate ' - '];

        % Đọc hàng dưới
        for i = 1:size(bottomChars, 1)
            idx = bottomChars(bottomOrder(i), 1);
            letter = Letter_detection(Iprops(idx).Image);
            noPlate = [noPlate letter];
        end
    else
        % Xử lý biển 1 hàng
        [~, order] = sort(charInfo(:, 2));
        for i = 1:size(charInfo, 1)
            idx = charInfo(order(i), 1);
            letter = Letter_detection(Iprops(idx).Image);
            noPlate = [noPlate letter];
        end
    end

    % Chuẩn hóa biển số theo quy tắc
    noPlate = standardizeLicensePlate(noPlate);
end

function plate = standardizeLicensePlate(plate)
    % Loại bỏ khoảng trắng và dấu gạch ngang
    plate = strrep(plate, ' ', '');
    plate = strrep(plate, '-', '');

    % Kiểm tra 3 ký tự đầu
    if length(plate) >= 3
        firstThree = plate(1:3);
        if ~(isstrprop(firstThree(1), 'digit') && isstrprop(firstThree(2), 'digit'))
            plate = plate(2:end); % Xóa ký tự đầu tiên
        end

        if length(plate) >= 3
            for i = 1:2
                if ~isstrprop(plate(i), 'digit')
                    plate(i) = '8'; % Thay thế bằng số 8 nếu là chữ
                end
            end

            if isstrprop(plate(3), 'digit')
                plate(3) = 'B'; % Thay thế bằng chữ B nếu là số
            end
        end
    end

    % Xử lý 5 ký tự cuối
    if length(plate) > 3
        lastFiveStart = max(4, length(plate) - 4);
        lastFive = plate(lastFiveStart:end);

        % Kiểm tra và chuyển đổi các ký tự cuối
        for i = 1:length(lastFive)
            if ~isstrprop(lastFive(i), 'digit')
                if lastFive(i) == 'B'
                    lastFive(i) = '8';
                elseif lastFive(i) == 'S'
                    lastFive(i) = '9';
                end
            end
        end

        % Cập nhật lại biển số
        plate = [plate(1:lastFiveStart-1) lastFive];
    end
end

function [boundingBox] = findLargestArea(props)
    areas = [props.Area];
    [~, idx] = max(areas);
    boundingBox = props(idx).BoundingBox;
end
