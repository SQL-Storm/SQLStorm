
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RN,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PrevScore
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) 
    WHERE 
        p.CreationDate > DATEADD(year, -1, '2024-10-01 12:34:56'::TIMESTAMP)
),
PostHistoryData AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        MAX(ph.CreationDate) OVER (PARTITION BY ph.PostId) AS MaxHistoryDate,
        LISTAGG(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END, ', ') WITHIN GROUP (ORDER BY ph.Comment) AS CloseReasons
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId, ph.PostHistoryTypeId, ph.CreationDate
),
AggregatedData AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.ViewCount,
        rp.Score,
        rp.CommentCount,
        rp.UpVotes,
        pd.CloseReasons,
        (rp.Score - rp.PrevScore) AS ScoreChange,
        CASE 
            WHEN rp.Score < 0 THEN 'Negative'
            WHEN rp.Score > 0 THEN 'Positive'
            ELSE 'Neutral'
        END AS ScoreTrend
    FROM 
        RankedPosts rp
    LEFT JOIN 
        PostHistoryData pd ON rp.PostId = pd.PostId
)

SELECT 
    ag.PostId,
    ag.Title,
    ag.CreationDate,
    ag.ViewCount,
    ag.Score,
    ag.CommentCount,
    ag.UpVotes,
    COALESCE(ag.CloseReasons, 'No close reasons') AS CloseReasons,
    ag.ScoreChange,
    ag.ScoreTrend,
    CASE 
        WHEN ag.ScoreTrend = 'Negative' AND ag.CommentCount > 5 THEN 'Watch'
        ELSE 'Normal'
    END AS MonitoringStatus
FROM 
    AggregatedData ag
WHERE 
    ag.ViewCount > 100
    AND ag.ScoreTrend = 'Positive'
    AND (ag.CloseReasons IS NULL OR ag.CloseReasons NOT LIKE '%Duplicate%')
ORDER BY 
    ag.CreationDate DESC
LIMIT 50;
