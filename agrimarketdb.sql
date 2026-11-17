-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Nov 17, 2026 at 10:06 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `agrimarketdb`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_Apply_Seasonal_Price_Adjustment` (IN `p_crop_category` VARCHAR(50), IN `p_percentage_change` DECIMAL(5,2), INOUT `p_affected_crops` INT)   BEGIN
    IF p_percentage_change < -50.00 OR p_percentage_change > 100.00 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Price adjustment percentage must be between -50% and +100%.';
    END IF;

    CASE p_crop_category
        WHEN 'ALL' THEN
            UPDATE Crop
            SET unit_price = ROUND(unit_price * (1 + p_percentage_change / 100), 2);
        ELSE
            UPDATE Crop
            SET unit_price = ROUND(unit_price * (1 + p_percentage_change / 100), 2)
            WHERE crop_category = p_crop_category;
    END CASE;

    SET p_affected_crops = p_affected_crops + ROW_COUNT();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_Audit_Low_Stock_Inventory` (IN `p_threshold` DECIMAL(10,2), OUT `p_flagged_count` INT)   BEGIN
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_inv_id INT;
    DECLARE v_avail_qty DECIMAL(10, 2);

    DECLARE cur_inventory CURSOR FOR
        SELECT inventory_id, available_quantity
        FROM Inventory
        WHERE available_quantity > 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    SET p_flagged_count = 0;
    OPEN cur_inventory;

    read_loop: LOOP
        FETCH cur_inventory INTO v_inv_id, v_avail_qty;
        IF v_done THEN
            LEAVE read_loop;
        END IF;

        IF v_avail_qty < p_threshold THEN
            UPDATE Inventory
            SET inventory_status = 'Low Stock'
            WHERE inventory_id = v_inv_id;

            SET p_flagged_count = p_flagged_count + 1;
        END IF;
    END LOOP;

    CLOSE cur_inventory;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_Record_Crop_Sale` (IN `p_harvest_id` INT, IN `p_buyer_id` INT, IN `p_market_id` INT, IN `p_sale_date` DATE, IN `p_quantity` DECIMAL(10,2), IN `p_unit_price` DECIMAL(10,2), OUT `p_new_sale_id` INT)   BEGIN
    DECLARE v_available_qty DECIMAL(10, 2);

    SELECT available_quantity INTO v_available_qty
    FROM Inventory
    WHERE harvest_id = p_harvest_id;

    IF v_available_qty IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No inventory record found for the specified harvest_id.';
    ELSEIF p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Sale quantity must be greater than zero.';
    ELSEIF v_available_qty < p_quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Insufficient available stock in inventory for this sale.';
    ELSE
        INSERT INTO Sale (harvest_id, buyer_id, market_id, sale_date, quantity, unit_price)
        VALUES (p_harvest_id, p_buyer_id, p_market_id, p_sale_date, p_quantity, p_unit_price);

        SET p_new_sale_id = LAST_INSERT_ID();

        UPDATE Inventory
        SET available_quantity = available_quantity - p_quantity,
            inventory_status = CASE 
                WHEN (available_quantity - p_quantity) = 0 THEN 'Out of Stock'
                WHEN (available_quantity - p_quantity) < 500 THEN 'Low Stock'
                ELSE 'Available'
            END
        WHERE harvest_id = p_harvest_id;
    END IF;
END$$

--
-- Functions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `fn_Calculate_Farmer_Age` (`p_dob` DATE) RETURNS INT(11) DETERMINISTIC BEGIN
    RETURN TIMESTAMPDIFF(YEAR, p_dob, CURDATE());
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `fn_Get_Farmer_Total_Revenue` (`p_farmer_id` INT) RETURNS DECIMAL(12,2) READS SQL DATA BEGIN
    DECLARE v_total_revenue DECIMAL(12, 2) DEFAULT 0.00;
    
    SELECT COALESCE(SUM(s.quantity * s.unit_price), 0.00)
    INTO v_total_revenue
    FROM Sale s
    INNER JOIN Harvest h ON s.harvest_id = h.harvest_id
    WHERE h.farmer_id = p_farmer_id;
    
    RETURN v_total_revenue;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `fn_Get_Remaining_Harvest_Stock` (`p_harvest_id` INT) RETURNS DECIMAL(10,2) READS SQL DATA BEGIN
    DECLARE v_stock DECIMAL(10, 2) DEFAULT 0.00;
    
    SELECT COALESCE(available_quantity, 0.00)
    INTO v_stock
    FROM Inventory
    WHERE harvest_id = p_harvest_id;
    
    RETURN v_stock;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `buyer`
--

CREATE TABLE `buyer` (
  `buyer_id` int(11) NOT NULL,
  `buyer_type` varchar(50) NOT NULL,
  `company_name` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `buyer`
--

INSERT INTO `buyer` (`buyer_id`, `buyer_type`, `company_name`) VALUES
(2, 'Wholesaler', 'Bengal Agro Ltd.'),
(4, 'Retailer', 'Green Dhaka Superstore'),
(6, 'Exporter', 'Sylhet Tea & Crop Exporters'),
(8, 'Wholesaler', 'Chittagong Grain Traders'),
(10, 'Retailer', 'Fresh Bazar BD'),
(12, 'Processor', 'Northern Food Processing'),
(14, 'Wholesaler', 'National Agro Corporation');

-- --------------------------------------------------------

--
-- Table structure for table `crop`
--

CREATE TABLE `crop` (
  `crop_id` int(11) NOT NULL,
  `crop_name` varchar(100) NOT NULL,
  `crop_type` varchar(50) NOT NULL,
  `crop_category` varchar(50) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `crop_duration` int(11) NOT NULL,
  `crop_specs` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`crop_specs`))
) ;

--
-- Dumping data for table `crop`
--

INSERT INTO `crop` (`crop_id`, `crop_name`, `crop_type`, `crop_category`, `unit_price`, `crop_duration`, `crop_specs`) VALUES
(1, 'BRRI dhan28', 'Cereal', 'Grain', 34.00, 120, '{\r\n    \"ideal_ph\": {\"min\": 5.5, \"max\": 6.8},\r\n    \"irrigation_interval_days\": 7,\r\n    \"climate_zone\": \"Tropical Monsoon\",\r\n    \"resistant_to\": [\"Blast\", \"Bacterial Blight\"],\r\n    \"organic_certified\": true\r\n}'),
(2, 'BRRI dhan29', 'Cereal', 'Grain', 30.00, 150, NULL),
(3, 'Potato (Diamant)', 'Tuber', 'Vegetable', 25.00, 90, '{\r\n    \"ideal_ph\": {\"min\": 5.0, \"max\": 6.5},\r\n    \"irrigation_interval_days\": 5,\r\n    \"climate_zone\": \"Cool Dry\",\r\n    \"resistant_to\": [\"Late Blight\", \"Scab\"],\r\n    \"organic_certified\": false\r\n}'),
(4, 'Jute (C-capsularis)', 'Fiber', 'Cash Crop', 65.00, 120, '{\r\n    \"ideal_ph\": {\"min\": 6.0, \"max\": 7.5},\r\n    \"irrigation_interval_days\": 10,\r\n    \"climate_zone\": \"Subtropical\",\r\n    \"resistant_to\": [\"Stem Rot\"],\r\n    \"organic_certified\": true\r\n}'),
(5, 'Lentil (Masoor)', 'Pulse', 'Legume', 110.00, 110, NULL),
(6, 'Mustard (Tori-7)', 'Oilseed', 'Oil', 95.00, 85, NULL),
(7, 'Tomato (BARI-11)', 'Fruit/Veg', 'Vegetable', 40.00, 75, NULL),
(8, 'Onion (Taherpuri)', 'Bulb', 'Spice', 55.00, 100, NULL),
(9, 'Garlic (Local)', 'Bulb', 'Spice', 120.00, 130, NULL),
(10, 'Green Chili (Bichitra)', 'Fruit/Veg', 'Spice', 60.00, 60, NULL),
(11, 'Wheat (BARI Gom-33)', 'Cereal', 'Grain', 38.00, 115, NULL),
(12, 'Brinjal (Uttara)', 'Fruit/Veg', 'Vegetable', 45.00, 70, NULL),
(13, 'Cabbage (Atlas-70)', 'Leafy', 'Vegetable', 28.00, 80, NULL),
(14, 'Cauliflower (Snowball)', 'Leafy', 'Vegetable', 35.00, 80, NULL),
(15, 'Watermelon (Big Family)', 'Fruit', 'Fruit', 30.00, 90, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `farmer`
--

CREATE TABLE `farmer` (
  `farmer_id` int(11) NOT NULL,
  `mentor_farmer_id` int(11) DEFAULT NULL,
  `nid_number` varchar(20) NOT NULL,
  `gender` varchar(10) NOT NULL,
  `date_of_birth` date NOT NULL,
  `certification_status` varchar(50) DEFAULT 'Uncertified'
) ;

--
-- Dumping data for table `farmer`
--

INSERT INTO `farmer` (`farmer_id`, `mentor_farmer_id`, `nid_number`, `gender`, `date_of_birth`, `certification_status`) VALUES
(1, NULL, '1985123456789', 'Male', '1985-05-10', 'Certified Organic'),
(3, 1, '1990234567890', 'Male', '1990-08-15', 'Uncertified'),
(5, NULL, '1982345678901', 'Male', '1982-03-22', 'GAP Certified'),
(7, 1, '1995456789012', 'Male', '1995-11-05', 'Uncertified'),
(9, NULL, '1988567890123', 'Male', '1988-07-18', 'Certified Organic'),
(11, 5, '1992678901234', 'Male', '1992-01-30', 'GAP Certified'),
(13, NULL, '1980789012345', 'Male', '1980-09-12', 'Uncertified'),
(15, 5, '1997890123456', 'Male', '1997-04-25', 'Certified Organic');

-- --------------------------------------------------------

--
-- Table structure for table `fertilizer`
--

CREATE TABLE `fertilizer` (
  `fertilizer_id` int(11) NOT NULL,
  `fertilizer_name` varchar(100) NOT NULL,
  `fertilizer_type` varchar(50) NOT NULL,
  `manufacturer` varchar(100) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `expiry_date` date NOT NULL
) ;

--
-- Dumping data for table `fertilizer`
--

INSERT INTO `fertilizer` (`fertilizer_id`, `fertilizer_name`, `fertilizer_type`, `manufacturer`, `price`, `expiry_date`) VALUES
(1, 'Urea', 'Nitrogen', 'BCIC', 22.00, '2028-12-31'),
(2, 'TSP (Triple Super Phosphate)', 'Phosphorus', 'BCIC', 27.00, '2028-10-31'),
(3, 'MOP (Muriate of Potash)', 'Potassium', 'BCIC', 20.00, '2028-11-30'),
(4, 'Gypsum', 'Sulphur/Calcium', 'Local Agro', 15.00, '2029-05-31'),
(5, 'Zinc Sulphate', 'Micronutrient', 'ACI Agrolink', 120.00, '2027-08-31'),
(6, 'Organic Vermicompost', 'Organic', 'Nature Care', 15.00, '2027-06-30'),
(7, 'DAP (Diammonium Phosphate)', 'Nitrogen/Phosphorus', 'BCIC', 25.00, '2028-09-30'),
(8, 'Boric Acid', 'Micronutrient', 'Syngenta BD', 180.00, '2027-12-31'),
(9, 'Magnesium Sulphate', 'Micronutrient', 'Autocrop Care', 90.00, '2028-04-30'),
(10, 'Bone Meal', 'Organic', 'Green Planet', 45.00, '2028-01-31'),
(11, 'NPK Complex', 'Compound', 'ACI Fertilizer', 55.00, '2028-07-31'),
(12, 'Compost Manure', 'Organic', 'Eco Agro', 10.00, '2026-12-31'),
(13, 'Super Gypsum', 'Sulphur', 'Confidence Agro', 18.00, '2028-03-31'),
(14, 'Liquid Bio-Fertilizer', 'Biological', 'Bio-Tech BD', 250.00, '2027-10-15'),
(15, 'Potassium Nitrate', 'Compound', 'Square Agro', 160.00, '2028-05-31');

-- --------------------------------------------------------

--
-- Table structure for table `fertilizer_usage`
--

CREATE TABLE `fertilizer_usage` (
  `farmer_id` int(11) NOT NULL,
  `crop_id` int(11) NOT NULL,
  `fertilizer_id` int(11) NOT NULL,
  `usage_date` date NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `application_method` varchar(100) NOT NULL
) ;

--
-- Dumping data for table `fertilizer_usage`
--

INSERT INTO `fertilizer_usage` (`farmer_id`, `crop_id`, `fertilizer_id`, `usage_date`, `quantity`, `application_method`) VALUES
(1, 1, 1, '2026-01-15', 50.00, 'Broadcasting'),
(1, 1, 2, '2026-01-15', 30.00, 'Basal Application'),
(3, 2, 1, '2026-02-10', 55.00, 'Top Dressing'),
(3, 9, 5, '2026-02-15', 10.00, 'Foliar Spray'),
(5, 3, 3, '2026-01-20', 40.00, 'Side Dressing'),
(5, 10, 11, '2026-03-10', 20.00, 'Broadcasting'),
(7, 4, 1, '2026-04-10', 45.00, 'Broadcasting'),
(7, 11, 1, '2025-12-20', 40.00, 'Top Dressing'),
(9, 5, 6, '2025-12-05', 100.00, 'Soil Mixing'),
(9, 12, 6, '2026-02-01', 80.00, 'Soil Mixing'),
(11, 6, 7, '2026-01-05', 35.00, 'Basal Application'),
(11, 13, 7, '2026-01-25', 30.00, 'Basal Application'),
(13, 7, 2, '2026-03-01', 25.00, 'Foliar Spray'),
(13, 14, 2, '2026-02-28', 25.00, 'Basal Application'),
(15, 8, 3, '2026-02-20', 30.00, 'Side Dressing');

-- --------------------------------------------------------

--
-- Table structure for table `harvest`
--

CREATE TABLE `harvest` (
  `harvest_id` int(11) NOT NULL,
  `farmer_id` int(11) NOT NULL,
  `crop_id` int(11) NOT NULL,
  `land_id` int(11) NOT NULL,
  `season_id` int(11) NOT NULL,
  `harvest_date` date NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `quality_grade` varchar(10) NOT NULL
) ;

--
-- Dumping data for table `harvest`
--

INSERT INTO `harvest` (`harvest_id`, `farmer_id`, `crop_id`, `land_id`, `season_id`, `harvest_date`, `quantity`, `quality_grade`) VALUES
(3, 3, 2, 3, 1, '2026-04-10', 3200.00, 'Grade B'),
(4, 5, 4, 4, 2, '2026-06-20', 1500.00, 'Grade A'),
(5, 7, 5, 5, 1, '2026-03-10', 1200.00, 'Grade B'),
(6, 9, 6, 6, 1, '2026-02-28', 950.00, 'Grade A'),
(7, 11, 7, 7, 2, '2026-05-15', 1800.00, 'Grade A'),
(8, 13, 8, 8, 1, '2026-03-20', 3500.00, 'Grade B'),
(9, 15, 9, 9, 1, '2026-04-05', 800.00, 'Grade A'),
(10, 3, 10, 10, 2, '2026-06-01', 1100.00, 'Grade A'),
(11, 5, 11, 11, 1, '2026-03-15', 2200.00, 'Grade B'),
(12, 7, 12, 12, 2, '2026-05-20', 1600.00, 'Grade A'),
(13, 9, 13, 13, 1, '2026-02-10', 2000.00, 'Grade B'),
(14, 11, 14, 14, 1, '2026-02-18', 2400.00, 'Grade A'),
(15, 13, 15, 15, 2, '2026-06-10', 5000.00, 'Grade A');

-- --------------------------------------------------------

--
-- Table structure for table `inventory`
--

CREATE TABLE `inventory` (
  `inventory_id` int(11) NOT NULL,
  `harvest_id` int(11) NOT NULL,
  `available_quantity` decimal(10,2) NOT NULL,
  `storage_location` varchar(255) NOT NULL,
  `storage_type` varchar(50) NOT NULL,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `inventory_status` varchar(50) NOT NULL
) ;

--
-- Dumping data for table `inventory`
--

INSERT INTO `inventory` (`inventory_id`, `harvest_id`, `available_quantity`, `storage_location`, `storage_type`, `last_updated`, `inventory_status`) VALUES
(3, 3, 2500.00, 'Patiya Silo, Chattogram', 'Warehouse', '2026-11-16 07:50:06', 'Available'),
(4, 4, 1500.00, 'Khulna Jute Warehouse', 'Dry Warehouse', '2026-11-16 07:50:06', 'Available'),
(5, 5, 1000.00, 'Comilla Grain Store', 'Dry Warehouse', '2026-11-16 07:50:06', 'Available'),
(6, 6, 950.00, 'Rangpur Oilseed Godown', 'Silo', '2026-11-16 07:50:06', 'Available'),
(7, 7, 1500.00, 'Gazipur Vegetable Hub', 'Cold Storage', '2026-11-16 07:50:06', 'Available'),
(8, 8, 3000.00, 'Bogra Spice Godown', 'Dry Warehouse', '2026-11-16 07:50:06', 'Available'),
(9, 9, 800.00, 'Bogra Cold Storage', 'Cold Storage', '2026-11-16 07:50:06', 'Available'),
(10, 10, 900.00, 'Chittagong Agro Store', 'Cold Storage', '2026-11-16 07:50:06', 'Available'),
(11, 11, 1800.00, 'Khulna Silo', 'Silo', '2026-11-16 07:50:06', 'Available'),
(12, 12, 1400.00, 'Comilla Cold Store', 'Cold Storage', '2026-11-16 07:50:06', 'Available'),
(13, 13, 1500.00, 'Rangpur Warehouse', 'Warehouse', '2026-11-16 07:50:06', 'Available'),
(14, 14, 2000.00, 'Gazipur Storage Unit', 'Cold Storage', '2026-11-16 07:50:06', 'Available'),
(15, 15, 4500.00, 'Tangail Fruit Market Godown', 'Open Shed', '2026-11-16 07:50:06', 'Available');

-- --------------------------------------------------------

--
-- Table structure for table `land`
--

CREATE TABLE `land` (
  `land_id` int(11) NOT NULL,
  `farmer_id` int(11) NOT NULL,
  `land_size` decimal(10,2) NOT NULL,
  `location` varchar(255) NOT NULL,
  `soil_type` varchar(50) NOT NULL,
  `ownership_type` varchar(50) NOT NULL
) ;

--
-- Dumping data for table `land`
--

INSERT INTO `land` (`land_id`, `farmer_id`, `land_size`, `location`, `soil_type`, `ownership_type`) VALUES
(1, 1, 2.50, 'Savar, Dhaka', 'Loamy', 'Owned'),
(2, 1, 1.75, 'Dhamrai, Dhaka', 'Clay', 'Leased'),
(3, 3, 3.20, 'Patiya, Chattogram', 'Alluvial', 'Owned'),
(4, 5, 5.00, 'Batiaghata, Khulna', 'Saline', 'Owned'),
(5, 7, 2.00, 'Chandina, Comilla', 'Loamy', 'Leased'),
(6, 9, 4.10, 'Pirganj, Rangpur', 'Sandy', 'Owned'),
(7, 11, 1.50, 'Kaliakair, Gazipur', 'Clay', 'Owned'),
(8, 13, 3.80, 'Shajahanpur, Bogra', 'Loamy', 'Owned'),
(9, 15, 2.25, 'Ghatail, Tangail', 'Clay', 'Leased'),
(10, 3, 1.80, 'Boalkhali, Chattogram', 'Alluvial', 'Owned'),
(11, 5, 2.60, 'Dumuria, Khulna', 'Saline', 'Leased'),
(12, 7, 3.00, 'Burichong, Comilla', 'Loamy', 'Owned'),
(13, 9, 2.10, 'Badalgachhi, Rangpur', 'Sandy', 'Leased'),
(14, 11, 4.00, 'Sreepur, Gazipur', 'Clay', 'Owned'),
(15, 13, 1.90, 'Sherpur, Bogra', 'Loamy', 'Owned');

-- --------------------------------------------------------

--
-- Table structure for table `market`
--

CREATE TABLE `market` (
  `market_id` int(11) NOT NULL,
  `market_name` varchar(100) NOT NULL,
  `location` varchar(255) NOT NULL,
  `contact_number` varchar(20) NOT NULL,
  `market_type` varchar(50) NOT NULL,
  `opening_time` time NOT NULL,
  `closing_time` time NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `market`
--

INSERT INTO `market` (`market_id`, `market_name`, `location`, `contact_number`, `market_type`, `opening_time`, `closing_time`) VALUES
(1, 'Karwan Bazar Wholesale Market', 'Tejgaon, Dhaka', '+88029112233', 'Wholesale', '04:00:00', '22:00:00'),
(2, 'Khatunganj Wholesale Market', 'Chittagong', '+88031611223', 'Wholesale', '06:00:00', '20:00:00'),
(3, 'Bandar Bazar', 'Sylhet Sadar, Sylhet', '+88082171122', 'Retail/Wholesale', '07:00:00', '21:00:00'),
(4, 'Boro Bazar', 'Khulna Sadar, Khulna', '+88041721133', 'Wholesale', '06:30:00', '20:30:00'),
(5, 'Rajshahi City Hat', 'Rajshahi Sadar', '+88072181144', 'Local Market', '08:00:00', '18:00:00'),
(6, 'Rangpur Town Bazar', 'Rangpur', '+88052161155', 'Retail', '07:30:00', '20:00:00'),
(7, 'Comilla Wholesale Market', 'Comilla', '+88081761166', 'Wholesale', '06:00:00', '21:00:00'),
(8, 'Bogra Mahasthan Hat', 'Bogra', '+88051671177', 'Local Market', '05:00:00', '17:00:00'),
(9, 'Gazipur Chowrasta Bazar', 'Gazipur', '+88029223344', 'Retail/Wholesale', '07:00:00', '22:00:00'),
(10, 'Narayanganj Port Bazar', 'Narayanganj', '+88029778899', 'Wholesale', '05:30:00', '21:00:00'),
(11, 'Barishal Launchghat Bazar', 'Barishal', '+88043161188', 'Retail/Wholesale', '06:00:00', '20:00:00'),
(12, 'Mymensingh Station Bazar', 'Mymensingh', '+8809161199', 'Wholesale', '06:30:00', '21:30:00'),
(13, 'Jashore Railgate Market', 'Jashore', '+88042168800', 'Local Market', '07:00:00', '19:00:00'),
(14, 'Tangail New Market', 'Tangail', '+88092155566', 'Retail', '08:00:00', '21:00:00');

-- --------------------------------------------------------

--
-- Table structure for table `market_stall`
--

CREATE TABLE `market_stall` (
  `market_id` int(11) NOT NULL,
  `stall_number` varchar(20) NOT NULL,
  `stall_size` decimal(10,2) NOT NULL,
  `rental_fee` decimal(10,2) NOT NULL
) ;

--
-- Dumping data for table `market_stall`
--

INSERT INTO `market_stall` (`market_id`, `stall_number`, `stall_size`, `rental_fee`) VALUES
(1, 'A-101', 150.00, 12000.00),
(1, 'A-102', 200.00, 15000.00),
(2, 'B-201', 300.00, 22000.00),
(2, 'B-202', 250.00, 18000.00),
(3, 'C-101', 120.00, 8000.00),
(4, 'D-105', 180.00, 11000.00),
(5, 'E-101', 100.00, 5000.00),
(6, 'F-102', 110.00, 6000.00),
(7, 'G-301', 220.00, 14000.00),
(8, 'H-101', 130.00, 7000.00),
(9, 'I-101', 160.00, 10000.00),
(10, 'J-201', 240.00, 16000.00),
(11, 'K-101', 140.00, 8500.00),
(12, 'L-101', 190.00, 13000.00);

-- --------------------------------------------------------

--
-- Table structure for table `payment`
--

CREATE TABLE `payment` (
  `payment_id` int(11) NOT NULL,
  `sale_id` int(11) NOT NULL,
  `payment_date` date NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_method` varchar(50) NOT NULL,
  `payment_status` varchar(50) NOT NULL,
  `transaction_id` varchar(100) NOT NULL
) ;

--
-- Dumping data for table `payment`
--

INSERT INTO `payment` (`payment_id`, `sale_id`, `payment_date`, `amount`, `payment_method`, `payment_status`, `transaction_id`) VALUES
(4, 4, '2026-04-12', 22050.00, 'Bank Transfer', 'Completed', 'TXN223344556'),
(5, 5, '2026-06-21', 27200.00, 'Mobile Banking (Nagad)', 'Completed', 'NGD334455667'),
(6, 6, '2026-03-11', 23000.00, 'Bank Transfer', 'Completed', 'TXN445566778'),
(7, 7, '2026-03-01', 14700.00, 'Cash', 'Completed', 'CSH556677889'),
(9, 9, '2026-04-15', 9600.00, 'Cash', 'Completed', 'CSH778899001'),
(10, 10, '2026-05-16', 12600.00, 'Bank Transfer', 'Completed', 'TXN889900112');

-- --------------------------------------------------------

--
-- Table structure for table `sale`
--

CREATE TABLE `sale` (
  `sale_id` int(11) NOT NULL,
  `harvest_id` int(11) NOT NULL,
  `buyer_id` int(11) NOT NULL,
  `market_id` int(11) NOT NULL,
  `sale_date` date NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL
) ;

--
-- Dumping data for table `sale`
--

INSERT INTO `sale` (`sale_id`, `harvest_id`, `buyer_id`, `market_id`, `sale_date`, `quantity`, `unit_price`) VALUES
(4, 3, 8, 2, '2026-04-12', 700.00, 31.50),
(5, 4, 10, 4, '2026-06-21', 400.00, 68.00),
(6, 5, 12, 7, '2026-03-11', 200.00, 115.00),
(7, 6, 14, 6, '2026-03-01', 150.00, 98.00),
(9, 3, 4, 9, '2026-04-15', 300.00, 32.00),
(10, 7, 6, 9, '2026-05-16', 300.00, 42.00),
(11, 8, 8, 8, '2026-03-21', 500.00, 57.00),
(12, 9, 10, 8, '2026-04-06', 200.00, 125.00),
(13, 10, 12, 2, '2026-06-02', 200.00, 62.00),
(14, 11, 14, 4, '2026-03-16', 400.00, 39.00),
(15, 12, 2, 7, '2026-05-21', 200.00, 46.00),
(16, 13, 4, 6, '2026-02-12', 500.00, 29.00),
(17, 14, 6, 9, '2026-02-19', 400.00, 29.50),
(18, 15, 8, 11, '2026-06-11', 500.00, 32.00),
(21, 3, 14, 2, '2026-04-18', 450.00, 31.00),
(22, 4, 2, 4, '2026-06-25', 350.00, 67.00),
(23, 5, 4, 7, '2026-03-15', 250.00, 112.00),
(24, 6, 6, 6, '2026-03-05', 300.00, 96.00),
(25, 7, 8, 9, '2026-05-18', 400.00, 41.00),
(26, 8, 10, 8, '2026-03-25', 600.00, 56.00),
(27, 9, 12, 8, '2026-04-10', 150.00, 122.00),
(28, 10, 14, 2, '2026-06-05', 300.00, 61.00),
(29, 11, 2, 4, '2026-03-20', 500.00, 38.50),
(30, 12, 4, 7, '2026-05-25', 350.00, 45.00),
(31, 13, 6, 6, '2026-02-15', 400.00, 29.50),
(32, 14, 8, 9, '2026-02-22', 450.00, 29.00),
(33, 15, 10, 11, '2026-06-15', 800.00, 31.00),
(36, 3, 2, 2, '2026-04-20', 550.00, 32.00),
(37, 4, 4, 4, '2026-06-28', 300.00, 69.00),
(38, 5, 6, 7, '2026-03-18', 180.00, 114.00),
(39, 6, 8, 6, '2026-03-08', 250.00, 97.00),
(40, 7, 10, 9, '2026-05-20', 350.00, 41.50),
(41, 8, 12, 8, '2026-03-28', 400.00, 58.00),
(42, 9, 14, 8, '2026-04-12', 250.00, 120.00),
(43, 10, 2, 2, '2026-06-08', 250.00, 63.00),
(44, 11, 4, 4, '2026-03-22', 300.00, 39.50),
(45, 12, 6, 7, '2026-05-28', 400.00, 44.50),
(46, 13, 8, 6, '2026-02-18', 350.00, 29.00),
(47, 14, 10, 9, '2026-02-25', 500.00, 28.50),
(48, 15, 12, 11, '2026-06-18', 600.00, 31.50),
(51, 3, 4, 2, '2026-04-22', 400.00, 31.80),
(52, 4, 6, 4, '2026-06-30', 500.00, 68.50),
(53, 5, 8, 7, '2026-03-20', 220.00, 113.00),
(54, 6, 10, 6, '2026-03-10', 300.00, 97.50),
(55, 7, 12, 9, '2026-05-22', 250.00, 42.00);

-- --------------------------------------------------------

--
-- Table structure for table `season`
--

CREATE TABLE `season` (
  `season_id` int(11) NOT NULL,
  `season_name` varchar(50) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `weather_type` varchar(50) NOT NULL
) ;

--
-- Dumping data for table `season`
--

INSERT INTO `season` (`season_id`, `season_name`, `start_date`, `end_date`, `weather_type`) VALUES
(1, 'Rabi 2025-26', '2025-11-01', '2026-03-31', 'Cold and Dry'),
(2, 'Kharif-1 2026', '2026-04-01', '2026-07-15', 'Hot and Humid'),
(3, 'Kharif-2 2026', '2026-07-16', '2026-10-31', 'Monsoon/Rainy'),
(4, 'Rabi 2026-27', '2026-11-01', '2027-03-31', 'Cold and Dry'),
(5, 'Kharif-1 2027', '2027-04-01', '2027-07-15', 'Hot and Humid'),
(6, 'Kharif-2 2027', '2027-07-16', '2027-10-31', 'Monsoon/Rainy'),
(7, 'Rabi 2023-24', '2023-11-01', '2024-03-31', 'Cold and Dry'),
(8, 'Kharif-1 2024', '2024-04-01', '2024-07-15', 'Hot and Humid'),
(9, 'Kharif-2 2024', '2024-07-16', '2024-10-31', 'Monsoon/Rainy'),
(10, 'Rabi 2024-25', '2024-11-01', '2025-03-31', 'Cold and Dry'),
(11, 'Kharif-1 2025', '2025-04-01', '2025-07-15', 'Hot and Humid'),
(12, 'Kharif-2 2025', '2025-07-16', '2025-10-31', 'Monsoon/Rainy'),
(13, 'Boro Season A', '2024-12-01', '2025-04-30', 'Moderate'),
(14, 'Aus Season A', '2025-04-15', '2025-08-15', 'Rainy'),
(15, 'Aman Season A', '2025-07-01', '2025-11-30', 'Monsoon');

-- --------------------------------------------------------

--
-- Table structure for table `shipment`
--

CREATE TABLE `shipment` (
  `shipment_id` int(11) NOT NULL,
  `sale_id` int(11) NOT NULL,
  `shipment_date` date NOT NULL,
  `delivery_date` date NOT NULL,
  `delivery_address` varchar(255) NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `shipment_status` varchar(50) NOT NULL,
  `transport_type` varchar(50) NOT NULL
) ;

--
-- Dumping data for table `shipment`
--

INSERT INTO `shipment` (`shipment_id`, `sale_id`, `shipment_date`, `delivery_date`, `delivery_address`, `quantity`, `shipment_status`, `transport_type`) VALUES
(4, 4, '2026-04-12', '2026-04-13', 'GEC Circle, Chattogram', 700.00, 'Delivered', 'Truck'),
(5, 5, '2026-06-21', '2026-06-22', 'Zindabazar, Sylhet', 400.00, 'Delivered', 'Covered Van'),
(6, 6, '2026-03-11', '2026-03-12', 'Sonadanga, Khulna', 200.00, 'Delivered', 'Truck'),
(7, 7, '2026-03-01', '2026-03-02', 'Shaheb Bazar, Rajshahi', 150.00, 'Delivered', 'Pickup Van'),
(9, 9, '2026-04-15', '2026-04-16', 'Mirpur-1, Dhaka', 300.00, 'Delivered', 'Covered Van'),
(10, 10, '2026-05-16', '2026-05-17', 'Comilla Sadar', 300.00, 'Delivered', 'Pickup Van');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `user_id` int(11) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `address` varchar(255) NOT NULL,
  `registration_date` date NOT NULL DEFAULT curdate()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`user_id`, `first_name`, `last_name`, `email`, `address`, `registration_date`) VALUES
(1, 'Abdul', 'Karim', 'abdul.karim@gmail.com', 'Mirpur-10, Dhaka', '2024-01-15'),
(2, 'Fatema', 'Begum', 'fatema.begum@gmail.com', 'Zindabazar, Sylhet', '2024-02-20'),
(3, 'Mohammad', 'Rahim', 'm.rahim@gmail.com', 'Sholokbahar, Chattogram', '2024-03-10'),
(4, 'Salma', 'Akter', 'salma.akter@gmail.com', 'Rajshahi Sadar, Rajshahi', '2024-04-05'),
(5, 'Nazmul', 'Hasan', 'nazmul.hasan@gmail.com', 'Town Hall, Khulna', '2024-05-12'),
(6, 'Nasrin', 'Akter', 'nasrin.akter@gmail.com', 'Jashore Sadar, Jashore', '2024-06-18'),
(7, 'Rafiqul', 'Islam', 'rafiqul.islam@gmail.com', 'Comilla Sadar, Comilla', '2024-07-22'),
(8, 'Shahanara', 'Parvin', 'shahanara.p@gmail.com', 'Barishal Sadar, Barishal', '2024-08-14'),
(9, 'Tanvir', 'Ahmed', 'tanvir.ahmed@gmail.com', 'Rangpur Sadar, Rangpur', '2024-09-01'),
(10, 'Monira', 'Sultana', 'monira.s@gmail.com', 'Mymensingh Sadar, Mymensingh', '2024-10-05'),
(11, 'Kamal', 'Hossain', 'kamal.hossain@gmail.com', 'Gazipur Sadar, Gazipur', '2024-11-11'),
(12, 'Jahanara', 'Khanam', 'jahanara.k@gmail.com', 'Narayanganj Sadar, Narayanganj', '2024-12-20'),
(13, 'Anisur', 'Rahman', 'anisur.r@gmail.com', 'Bogra Sadar, Bogra', '2025-01-08'),
(14, 'Parvin', 'Akter', 'parvin.akter@gmail.com', 'Pabna Sadar, Pabna', '2025-02-14'),
(15, 'Shahidul', 'Islam', 'shahidul.i@gmail.com', 'Tangail Sadar, Tangail', '2025-03-01');

-- --------------------------------------------------------

--
-- Table structure for table `user_phone`
--

CREATE TABLE `user_phone` (
  `user_id` int(11) NOT NULL,
  `phone_number` varchar(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `user_phone`
--

INSERT INTO `user_phone` (`user_id`, `phone_number`) VALUES
(1, '+8801711223344'),
(2, '+8801811556677'),
(3, '+8801911889900'),
(4, '+8801511223355'),
(5, '+8801611445566'),
(6, '+8801722334455'),
(7, '+8801822556688'),
(8, '+8801922889911'),
(9, '+8801522334466'),
(10, '+8801622445577'),
(11, '+8801733223344'),
(12, '+8801833556677'),
(13, '+8801933889900'),
(14, '+8801533223355'),
(15, '+8801633445566');

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_crop_catalog`
-- (See below for the actual view)
--
CREATE TABLE `vw_crop_catalog` (
`crop_id` int(11)
,`crop_name` varchar(100)
,`crop_category` varchar(50)
,`unit_price` decimal(10,2)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_gradea_harvests`
-- (See below for the actual view)
--
CREATE TABLE `vw_gradea_harvests` (
`harvest_id` int(11)
,`farmer_id` int(11)
,`crop_id` int(11)
,`land_id` int(11)
,`season_id` int(11)
,`harvest_date` date
,`quantity` decimal(10,2)
,`quality_grade` varchar(10)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_market_crop_sales_summary`
-- (See below for the actual view)
--
CREATE TABLE `vw_market_crop_sales_summary` (
`market_id` int(11)
,`market_name` varchar(100)
,`crop_name` varchar(100)
,`total_transactions` bigint(21)
,`total_quantity_sold` decimal(32,2)
,`total_revenue` decimal(42,4)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_public_farmer_directory`
-- (See below for the actual view)
--
CREATE TABLE `vw_public_farmer_directory` (
`farmer_id` int(11)
,`farmer_name` varchar(101)
,`district_location` varchar(255)
,`gender` varchar(10)
,`certification_status` varchar(50)
);

-- --------------------------------------------------------

--
-- Structure for view `vw_crop_catalog`
--
DROP TABLE IF EXISTS `vw_crop_catalog`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_crop_catalog`  AS SELECT `crop`.`crop_id` AS `crop_id`, `crop`.`crop_name` AS `crop_name`, `crop`.`crop_category` AS `crop_category`, `crop`.`unit_price` AS `unit_price` FROM `crop` ;

-- --------------------------------------------------------

--
-- Structure for view `vw_gradea_harvests`
--
DROP TABLE IF EXISTS `vw_gradea_harvests`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_gradea_harvests`  AS SELECT `harvest`.`harvest_id` AS `harvest_id`, `harvest`.`farmer_id` AS `farmer_id`, `harvest`.`crop_id` AS `crop_id`, `harvest`.`land_id` AS `land_id`, `harvest`.`season_id` AS `season_id`, `harvest`.`harvest_date` AS `harvest_date`, `harvest`.`quantity` AS `quantity`, `harvest`.`quality_grade` AS `quality_grade` FROM `harvest` WHERE `harvest`.`quality_grade` = 'Grade A'WITH CASCADED CHECK OPTION  ;

-- --------------------------------------------------------

--
-- Structure for view `vw_market_crop_sales_summary`
--
DROP TABLE IF EXISTS `vw_market_crop_sales_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_market_crop_sales_summary`  AS SELECT `m`.`market_id` AS `market_id`, `m`.`market_name` AS `market_name`, `c`.`crop_name` AS `crop_name`, count(`s`.`sale_id`) AS `total_transactions`, sum(`s`.`quantity`) AS `total_quantity_sold`, sum(`s`.`quantity` * `s`.`unit_price`) AS `total_revenue` FROM (((`market` `m` join `sale` `s` on(`m`.`market_id` = `s`.`market_id`)) join `harvest` `h` on(`s`.`harvest_id` = `h`.`harvest_id`)) join `crop` `c` on(`h`.`crop_id` = `c`.`crop_id`)) GROUP BY `m`.`market_id`, `m`.`market_name`, `c`.`crop_id`, `c`.`crop_name` ;

-- --------------------------------------------------------

--
-- Structure for view `vw_public_farmer_directory`
--
DROP TABLE IF EXISTS `vw_public_farmer_directory`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_public_farmer_directory`  AS SELECT `u`.`user_id` AS `farmer_id`, concat(`u`.`first_name`,' ',`u`.`last_name`) AS `farmer_name`, `u`.`address` AS `district_location`, `f`.`gender` AS `gender`, `f`.`certification_status` AS `certification_status` FROM (`users` `u` join `farmer` `f` on(`u`.`user_id` = `f`.`farmer_id`)) ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `buyer`
--
ALTER TABLE `buyer`
  ADD PRIMARY KEY (`buyer_id`);

--
-- Indexes for table `crop`
--
ALTER TABLE `crop`
  ADD PRIMARY KEY (`crop_id`);

--
-- Indexes for table `farmer`
--
ALTER TABLE `farmer`
  ADD PRIMARY KEY (`farmer_id`),
  ADD UNIQUE KEY `nid_number` (`nid_number`),
  ADD KEY `fk_farmer_mentor` (`mentor_farmer_id`);

--
-- Indexes for table `fertilizer`
--
ALTER TABLE `fertilizer`
  ADD PRIMARY KEY (`fertilizer_id`);

--
-- Indexes for table `fertilizer_usage`
--
ALTER TABLE `fertilizer_usage`
  ADD PRIMARY KEY (`farmer_id`,`crop_id`,`fertilizer_id`,`usage_date`),
  ADD KEY `fk_fert_crop` (`crop_id`),
  ADD KEY `fk_fert_fertilizer` (`fertilizer_id`);

--
-- Indexes for table `harvest`
--
ALTER TABLE `harvest`
  ADD PRIMARY KEY (`harvest_id`),
  ADD KEY `fk_harvest_farmer` (`farmer_id`),
  ADD KEY `fk_harvest_crop` (`crop_id`),
  ADD KEY `fk_harvest_land` (`land_id`),
  ADD KEY `fk_harvest_season` (`season_id`);

--
-- Indexes for table `inventory`
--
ALTER TABLE `inventory`
  ADD PRIMARY KEY (`inventory_id`),
  ADD UNIQUE KEY `harvest_id` (`harvest_id`);

--
-- Indexes for table `land`
--
ALTER TABLE `land`
  ADD PRIMARY KEY (`land_id`),
  ADD KEY `fk_land_farmer` (`farmer_id`);

--
-- Indexes for table `market`
--
ALTER TABLE `market`
  ADD PRIMARY KEY (`market_id`);

--
-- Indexes for table `market_stall`
--
ALTER TABLE `market_stall`
  ADD PRIMARY KEY (`market_id`,`stall_number`);

--
-- Indexes for table `payment`
--
ALTER TABLE `payment`
  ADD PRIMARY KEY (`payment_id`),
  ADD UNIQUE KEY `sale_id` (`sale_id`),
  ADD UNIQUE KEY `transaction_id` (`transaction_id`);

--
-- Indexes for table `sale`
--
ALTER TABLE `sale`
  ADD PRIMARY KEY (`sale_id`),
  ADD KEY `fk_sale_harvest` (`harvest_id`),
  ADD KEY `fk_sale_buyer` (`buyer_id`),
  ADD KEY `fk_sale_market` (`market_id`);

--
-- Indexes for table `season`
--
ALTER TABLE `season`
  ADD PRIMARY KEY (`season_id`);

--
-- Indexes for table `shipment`
--
ALTER TABLE `shipment`
  ADD PRIMARY KEY (`shipment_id`),
  ADD KEY `fk_shipment_sale` (`sale_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `user_phone`
--
ALTER TABLE `user_phone`
  ADD PRIMARY KEY (`user_id`,`phone_number`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `crop`
--
ALTER TABLE `crop`
  MODIFY `crop_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `fertilizer`
--
ALTER TABLE `fertilizer`
  MODIFY `fertilizer_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `harvest`
--
ALTER TABLE `harvest`
  MODIFY `harvest_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `inventory`
--
ALTER TABLE `inventory`
  MODIFY `inventory_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `land`
--
ALTER TABLE `land`
  MODIFY `land_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `market`
--
ALTER TABLE `market`
  MODIFY `market_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `payment`
--
ALTER TABLE `payment`
  MODIFY `payment_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `sale`
--
ALTER TABLE `sale`
  MODIFY `sale_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `season`
--
ALTER TABLE `season`
  MODIFY `season_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `shipment`
--
ALTER TABLE `shipment`
  MODIFY `shipment_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `user_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=46;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `buyer`
--
ALTER TABLE `buyer`
  ADD CONSTRAINT `fk_buyer_user` FOREIGN KEY (`buyer_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `farmer`
--
ALTER TABLE `farmer`
  ADD CONSTRAINT `fk_farmer_mentor` FOREIGN KEY (`mentor_farmer_id`) REFERENCES `farmer` (`farmer_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_farmer_user` FOREIGN KEY (`farmer_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `fertilizer_usage`
--
ALTER TABLE `fertilizer_usage`
  ADD CONSTRAINT `fk_fert_crop` FOREIGN KEY (`crop_id`) REFERENCES `crop` (`crop_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_fert_farmer` FOREIGN KEY (`farmer_id`) REFERENCES `farmer` (`farmer_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_fert_fertilizer` FOREIGN KEY (`fertilizer_id`) REFERENCES `fertilizer` (`fertilizer_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `harvest`
--
ALTER TABLE `harvest`
  ADD CONSTRAINT `fk_harvest_crop` FOREIGN KEY (`crop_id`) REFERENCES `crop` (`crop_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_harvest_farmer` FOREIGN KEY (`farmer_id`) REFERENCES `farmer` (`farmer_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_harvest_land` FOREIGN KEY (`land_id`) REFERENCES `land` (`land_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_harvest_season` FOREIGN KEY (`season_id`) REFERENCES `season` (`season_id`) ON UPDATE CASCADE;

--
-- Constraints for table `inventory`
--
ALTER TABLE `inventory`
  ADD CONSTRAINT `fk_inventory_harvest` FOREIGN KEY (`harvest_id`) REFERENCES `harvest` (`harvest_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `land`
--
ALTER TABLE `land`
  ADD CONSTRAINT `fk_land_farmer` FOREIGN KEY (`farmer_id`) REFERENCES `farmer` (`farmer_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `market_stall`
--
ALTER TABLE `market_stall`
  ADD CONSTRAINT `fk_stall_market` FOREIGN KEY (`market_id`) REFERENCES `market` (`market_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `payment`
--
ALTER TABLE `payment`
  ADD CONSTRAINT `fk_payment_sale` FOREIGN KEY (`sale_id`) REFERENCES `sale` (`sale_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `sale`
--
ALTER TABLE `sale`
  ADD CONSTRAINT `fk_sale_buyer` FOREIGN KEY (`buyer_id`) REFERENCES `buyer` (`buyer_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sale_harvest` FOREIGN KEY (`harvest_id`) REFERENCES `harvest` (`harvest_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sale_market` FOREIGN KEY (`market_id`) REFERENCES `market` (`market_id`) ON UPDATE CASCADE;

--
-- Constraints for table `shipment`
--
ALTER TABLE `shipment`
  ADD CONSTRAINT `fk_shipment_sale` FOREIGN KEY (`sale_id`) REFERENCES `sale` (`sale_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `user_phone`
--
ALTER TABLE `user_phone`
  ADD CONSTRAINT `fk_user_phone` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
