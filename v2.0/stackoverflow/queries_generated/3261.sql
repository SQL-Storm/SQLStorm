-- {"query": "3261.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2769} 
WITH 
UserStats AS (
    SELECT 
        u.Id,
        COALESCE(u.DisplayName,'Anonymous') AS DisplayName,
        u.Reputation,
        COALESCE(u.Location,'Unknown') AS Location,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
), 
PostScoreRank AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.OwnerUserId IS NOT NULL
), 
TagInfo AS (
    SELECT 
        t.TagName,
        t.Count AS TagUseCount,
        CASE 
            WHEN t.IsModeratorOnly = 1 THEN 'ModeratorOnly'
            WHEN t.IsRequired = 1 THEN 'Required'
            ELSE 'Normal' 
        END AS TagCategory,
        COALESCE(e.Title,'') AS ExcerptTitle,
        COALESCE(w.Title,'') AS WikiTitle
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
), 
UserTopPosts AS (
    SELECT 
        us.Id AS UserId,
        ps.Id AS PostId,
        ps.Score,
        ps.ScoreRank,
        CASE WHEN ps.ScoreRank = 1 THEN 'TopScore' END AS TopScoreFlag,
        CASE WHEN ps.RowNum = 1 THEN 'FirstPost' END AS FirstPostFlag
    FROM UserStats us
    JOIN PostScoreRank ps ON ps.OwnerUserId = us.Id
    WHERE ps.ScoreRank <= 3
), 
VoteAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(CASE WHEN vt.Id = 5 THEN v.UserId END) AS FavoriteUserId
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
), 
HighRepUsers AS (
    SELECT Id FROM Users WHERE Reputation > 100000
) 
SELECT 
    us.Id AS UserId,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.QuestionCount,
    us.AnswerCount,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    utp.PostId,
    utp.Score,
    utp.ScoreRank,
    utp.TopScoreFlag,
    utp.FirstPostFlag,
    COALESCE(va.UpVotes,0) AS UpVotes,
    COALESCE(va.DownVotes,0) AS DownVotes,
    CASE WHEN va.FavoriteUserId IS NOT NULL THEN 'Favorited' ELSE 'NotFav' END AS FavoriteStatus,
    ti.TagName,
    ti.TagUseCount,
    ti.TagCategory,
    CASE 
        WHEN us.Reputation > 100000 THEN 'HighRep'
        WHEN us.Reputation BETWEEN 1000 AND 100000 THEN 'MidRep'
        ELSE 'LowRep' 
    END AS RepTier,
    CONCAT('U_', us.Id) AS UserKey
FROM UserStats us
LEFT JOIN UserTopPosts utp ON utp.UserId = us.Id
LEFT JOIN VoteAgg va ON va.PostId = utp.PostId
LEFT JOIN TagInfo ti ON ti.TagUseCount > 5000
WHERE us.QuestionCount > 0

UNION ALL

SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    p.Id,
    p.Score,
    NULL,
    NULL,
    NULL,
    0,0,'NoFav',
    NULL,NULL,NULL,
    CASE 
        WHEN p.Score > 500 THEN 'HighScore' 
        ELSE 'LowScore' 
    END,
    CONCAT('Q_',p.Id)
FROM Posts p
WHERE p.PostTypeId = 1 AND p.Score > 100

EXCEPT

SELECT *
FROM (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.QuestionCount,
        us.AnswerCount,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        utp.PostId,
        utp.Score,
        utp.ScoreRank,
        utp.TopScoreFlag,
        utp.FirstPostFlag,
        COALESCE(va.UpVotes,0),
        COALESCE(va.DownVotes,0),
        CASE WHEN va.FavoriteUserId IS NOT NULL THEN 'Favorited' ELSE 'NotFav' END,
        ti.TagName,
        ti.TagUseCount,
        ti.TagCategory,
        CASE 
            WHEN us.Reputation > 100000 THEN 'HighRep'
            WHEN us.Reputation BETWEEN 1000 AND 100000 THEN 'MidRep'
            ELSE 'LowRep' 
        END,
        CONCAT('U_', us.Id)
    FROM UserStats us
    LEFT JOIN UserTopPosts utp ON utp.UserId = us.Id
    LEFT JOIN VoteAgg va ON va.PostId = utp.PostId
    LEFT JOIN TagInfo ti ON ti.TagUseCount > 5000
    WHERE us.QuestionCount > 0
) AS Excluded;