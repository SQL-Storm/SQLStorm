WITH RankedUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        (
         SELECT 
             UserId, 
             COUNT(*) AS TotalBadges
         FROM 
             Badges
         GROUP BY 
             UserId
        ) b ON u.Id = b.UserId
    WHERE 
        b.TotalBadges IS NOT NULL AND u.Reputation > 1000
),
TopPerformingPosts AS (
    SELECT 
        p.Id, 
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND 
        p.Score > 50 AND 
        p.ViewCount > 1000 AND
        (p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<benchmarking>%')
),
UserPostAnalysis AS (
    SELECT 
        ru.Id AS UserId,
        ru.DisplayName,
        tpp.Id AS PostId,
        tpp.Title,
        tpp.Score,
        tpp.ViewCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tpp.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tpp.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        COALESCE(
            (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = tpp.Id AND ph.PostHistoryTypeId IN (5, 8)),
            tpp.CreationDate
        ) AS LastEditDate
    FROM 
        RankedUsers ru
    JOIN 
        TopPerformingPosts tpp ON ru.Id = tpp.OwnerUserId
    WHERE 
        tpp.PostRank <= 3
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.PostId,
    upa.Title,
    (upa.Score * 1.0) / NULLIF(upa.ViewCount,0) AS ScoreToViewRatio,
    upa.CommentCount,
    upa.UpVoteCount,
    CASE 
        WHEN upa.LastEditDate = tpp.CreationDate THEN 'Never Edited'
        ELSE 'Edited'
    END AS EditStatus
FROM 
    UserPostAnalysis upa
JOIN 
    TopPerformingPosts tpp ON upa.PostId = tpp.Id
ORDER BY 
    ScoreToViewRatio DESC
FETCH FIRST 10 ROWS ONLY;