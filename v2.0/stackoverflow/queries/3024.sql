-- {"query": "3024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2389} 
WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id)                         AS TotalBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)        AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2)        AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3)        AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2)    AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3)    AS DownVotesGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate)               AS RankByRep
    FROM Users u
    WHERE u.Reputation >= 1000
),

RecentActivity AS (
    SELECT 
        u.Id,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(v.CreationDate)     AS LastVoteGiven,
        MAX(c.CreationDate)     AS LastCommentMade
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes    v ON v.UserId      = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
),

TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                                 AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                                 AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)                                AS TotalQuestionScore,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)                                AS TotalAnswerScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                                AS AvgQuestionScore,
        ROW_NUMBER() OVER (ORDER BY 
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) DESC)                       AS TopTagRank
    FROM Tags t
    JOIN Posts p 
      ON p.Tags IS NOT NULL
     AND ('<' || replace(t.TagName, ' ', '') || '>') = ANY(string_to_array(p.Tags, '><'))
    GROUP BY t.TagName
    HAVING COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) > 100
),

DuplicateLinks AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name                                                       AS LinkTypeName,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),

FinalResult AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalBadges,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        us.UpVotesGiven,
        us.DownVotesGiven,
        us.RankByRep,
        ra.LastPostActivity,
        ra.LastVoteGiven,
        ra.LastCommentMade,
        COALESCE(dl.RelatedPostId, -1)                               AS MostRecentDuplicateOf,
        dl.CreationDate                                                AS DuplicateLinkDate
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
    LEFT JOIN DuplicateLinks dl 
           ON dl.PostId = (
                 SELECT p.Id 
                 FROM Posts p 
                 WHERE p.OwnerUserId = us.Id AND p.PostTypeId = 1 
                 ORDER BY p.CreationDate DESC 
                 LIMIT 1
               )
          AND dl.rn = 1
)

SELECT *
FROM FinalResult
WHERE RankByRep <= 50

UNION ALL

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.TotalBadges,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    us.RankByRep,
    ra.LastPostActivity,
    ra.LastVoteGiven,
    ra.LastCommentMade,
    -1                                                            AS MostRecentDuplicateOf,
    NULL                                                          AS DuplicateLinkDate
FROM UserStats us
JOIN RecentActivity ra ON ra.Id = us.Id
WHERE us.TotalBadges = (SELECT MAX(TotalBadges) FROM UserStats)

ORDER BY RankByRep;