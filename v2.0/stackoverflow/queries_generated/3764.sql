-- {"query": "3764.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2298} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(bc.TotalBadges,0)   AS TotalBadges,
        COALESCE(bc.GoldBadges,0)    AS GoldBadges,
        COALESCE(bc.SilverBadges,0)  AS SilverBadges,
        COALESCE(bc.BronzeBadges,0)  AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(*)                                             AS TotalBadges,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END)          AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END)          AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END)          AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
    WHERE u.Reputation > 1000
),
RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
TopRecentPosts AS (
    SELECT *
    FROM RecentPosts
    WHERE rn <= 5
),
TagAggregates AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                AS PostCount,
        SUM(p.Score)               AS ScoreSum,
        AVG(p.Score)               AS ScoreAvg,
        MAX(p.CreationDate)        AS LatestPostDate
    FROM Tags t
    JOIN Posts p
        ON p.Tags IS NOT NULL
        AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
),
UserPostStats AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalBadges,
        us.QuestionCount,
        us.AnswerCount,
        COALESCE(SUM(vc.UpVotes),0)     AS UpVoteSum,
        COALESCE(SUM(vc.DownVotes),0)   AS DownVoteSum,
        COALESCE(COUNT(DISTINCT pl.RelatedPostId),0) AS LinkedPostsCount,
        ROW_NUMBER() OVER (ORDER BY (us.Reputation * (us.TotalBadges+1)) DESC) AS ScoreRank
    FROM UserStats us
    LEFT JOIN Posts p
        ON p.OwnerUserId = us.Id
    LEFT JOIN (
        SELECT
            v.PostId,
            CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END AS UpVotes,
            CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END AS DownVotes
        FROM Votes v
    ) vc ON vc.PostId = p.Id
    LEFT JOIN PostLinks pl
        ON pl.PostId = p.Id AND pl.LinkTypeId = 1
    GROUP BY
        us.Id, us.DisplayName, us.Reputation, us.TotalBadges,
        us.QuestionCount, us.AnswerCount
)
SELECT
    ups.Id,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalBadges,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.UpVoteSum,
    ups.DownVoteSum,
    ups.LinkedPostsCount,
    ups.ScoreRank,
    STRING_AGG(DISTINCT tp.Title, '; ') FILTER (WHERE tp.Title IS NOT NULL) AS RecentTopTitles,
    STRING_AGG(DISTINCT ta.TagName, ', ') FILTER (WHERE ta.TagName IS NOT NULL) AS PopularTags
FROM UserPostStats ups
LEFT JOIN TopRecentPosts tp
    ON tp.OwnerUserId = ups.Id
LEFT JOIN TagAggregates ta
    ON POSITION('<' || ta.TagName || '>' IN COALESCE(tp.Tags,'')) > 0
GROUP BY
    ups.Id, ups.DisplayName, ups.Reputation, ups.TotalBadges,
    ups.QuestionCount, ups.AnswerCount, ups.UpVoteSum,
    ups.DownVoteSum, ups.LinkedPostsCount, ups.ScoreRank
HAVING ups.ScoreRank <= 100

UNION ALL

SELECT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    STRING_AGG(ta.TagName, ', ') AS AllPopularTags,
    NULL
FROM TagAggregates ta
WHERE ta.ScoreAvg > 0

ORDER BY
    ScoreRank ASC NULLS LAST,
    AllPopularTags DESC NULLS LAST
LIMIT 200;
