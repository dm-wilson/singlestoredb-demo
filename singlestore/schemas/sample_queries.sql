-- Page Counts - Total Page Views 
SELECT 
    FROM_UNIXTIME(interval_start_unixtime), 
    SUM(count) as pageviews
FROM wikipedia.pagecounts 
GROUP BY interval_start_unixtime
ORDER BY interval_start_unixtime ASC; 

-- Page Counts - Total Page Views (By Project)
SELECT 
    FROM_UNIXTIME(interval_start_unixtime), 
    project_name, 
    SUM(count) as pageviews
FROM wikipedia.pagecounts 
WHERE project_name = 'en' 
GROUP BY interval_start_unixtime
ORDER BY interval_start_unixtime ASC; 

-- Page Counts - Total Page Views (By Article)
SELECT 
    FROM_UNIXTIME(interval_start_unixtime), 
    article_name, 
    SUM(count) as pageviews
FROM wikipedia.pagecounts 
WHERE article_name = 'Leslie_Lamport' 
GROUP BY interval_start_unixtime
ORDER BY interval_start_unixtime ASC; 

-- Total Bytes Served
SELECT 
    date as d, 
    sum(total_response_bytes) / POWER(10, 12)  as tb_served,
    sum(total_transfers_all) as n_imgs_served
FROM wikipedia.mediacounts 
GROUP BY date
ORDER BY date;
