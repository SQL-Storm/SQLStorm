WITH 
UserAgg AS (
    SELECT 
        u.Id                                 AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate                       AS UserCreated,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCnt,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCnt
    FROM Users u
    WHERE u.Reputation >= 500
),

RecentActivity AS (
    SELECT 
        p.OwnerUserId                            AS UserId,
        MAX(p.CreationDate)                     AS LastPostDate,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate ELSE NULL END) AS LastUpVoteDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),

TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                             AS TagPostCnt,
        SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TagScoreSum,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
                 AND p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 20
),

PostRank AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        COALESCE(p.Score * LOG(1 + p.ViewCount), 0) AS CompositeScore,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY COALESCE(p.Score * LOG(1 + p.ViewCount), 0) DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),

HighImpactUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionCnt,
        ua.AnswerCnt,
        COALESCE(ra.LastPostDate, TIMESTAMP '1970-01-01')      AS LastPostDate,
        COALESCE(ra.LastUpVoteDate, TIMESTAMP '1970-01-01')   AS LastUpVoteDate,
        CASE 
            WHEN ua.Reputation >= 10000 THEN 'Legendary'
            WHEN ua.Reputation BETWEEN 5000 AND 9999 THEN 'Power'
            WHEN ua.Reputation BETWEEN 2000 AND 4999 THEN 'Experienced'
            ELSE 'Rising'
        END                                          AS ReputationTier,
        (SELECT STRING_AGG(t.TagName, ', ') 
         FROM Tags t
         JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
         WHERE p.OwnerUserId = ua.UserId
         GROUP BY t.TagName
         ORDER BY COUNT(*) DESC
         LIMIT 3)                                 AS Top3Tags,
        EXISTS (SELECT 1 
                FROM PostHistory ph 
                WHERE ph.UserId = ua.UserId 
                  AND ph.PostHistoryTypeId = 10)    AS EverClosedFlag
    FROM UserAgg ua
    LEFT JOIN RecentActivity ra ON ra.UserId = ua.UserId
    WHERE (ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges) >= 3
),

CombinedUsers AS (
    SELECT *
    FROM HighImpactUsers
    UNION ALL
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        0,0,0,
        0,0,
        NULL,NULL,
        'Newcomer'          AS ReputationTier,
        NULL                AS Top3Tags,
        FALSE               AS EverClosedFlag
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE b.Id IS NULL
      AND u.Reputation < 200
)

SELECT 
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.QuestionCnt,
    cu.AnswerCnt,
    cu.LastPostDate,
    cu.LastUpVoteDate,
    cu.ReputationTier,
    cu.Top3Tags,
    cu.EverClosedFlag,
    ts.TagName               AS PopularTag,
    ts.TagPostCnt            AS TagPostCount,
    ts.TagScoreSum           AS TagScoreTotal,
    pr.Title                 AS TopScoringPost,
    pr.CompositeScore,
    pr.ScoreRank
FROM CombinedUsers cu
LEFT JOIN TagStats ts               ON ts.TagRank = 1
LEFT JOIN PostRank pr               ON pr.ScoreRank = 1
GROUP BY
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.QuestionCnt,
    cu.AnswerCnt,
    cu.LastPostDate,
    cu.LastUpVoteDate,
    cu.ReputationTier,
    cu.Top3Tags,
    cu.EverClosedFlag,
    ts.TagName,
    ts.TagPostCnt,
    ts.TagScoreSum,
    pr.Title,
    pr.CompositeScore,
    pr.ScoreRank
ORDER BY 
    CASE cu.ReputationTier 
        WHEN 'Legendary'   THEN 1
        WHEN 'Power'       THEN 2
        WHEN 'Experienced' THEN 3
        WHEN 'Rising'      THEN 4
        ELSE 5
    END,
    cu.GoldBadges DESC,
    cu.AnswerCnt DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;