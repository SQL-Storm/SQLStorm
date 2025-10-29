-- {"query": "3604.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2187}
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(vu.UpVotes), 0) AS UpVoteCount,
        COALESCE(SUM(vd.DownVotes), 0) AS DownVoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge
    FROM Users u
    LEFT JOIN Posts p               ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT v.PostId, COUNT(*) AS UpVotes
        FROM Votes v
        WHERE v.VoteTypeId = 2
        GROUP BY v.PostId
    ) vu                             ON vu.PostId = p.Id
    LEFT JOIN (
        SELECT v.PostId, COUNT(*) AS DownVotes
        FROM Votes v
        WHERE v.VoteTypeId = 3
        GROUP BY v.PostId
    ) vd                             ON vd.PostId = p.Id
    LEFT JOIN Badges b               ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.UpVoteCount,
        us.DownVoteCount,
        us.LastPostDate,
        us.HasGoldBadge,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, (us.QuestionCount + us.AnswerCount) DESC) AS rn
    FROM UserStats us
    WHERE us.Reputation > 5000
      AND us.HasGoldBadge = 1
),
LatestPosts AS (
    SELECT
        u.Id AS UserId,
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS seq
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TagAnalytics AS (
    SELECT
        t.TagName,
        COUNT(*) AS TaggedQuestionCount,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCount,
        AVG(p.ViewCount) FILTER (WHERE p.ViewCount IS NOT NULL) AS AvgViews
    FROM Tags t
    JOIN Posts p
      ON p.Tags ILIKE '%' || '<' || t.TagName || '>' || '%'
     AND p.PostTypeId = 1
    GROUP BY t.TagName
),
Combined AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.UpVoteCount,
        tu.DownVoteCount,
        lp.Title                           AS LatestQuestionTitle,
        lp.CreationDate                    AS LatestQuestionDate,
        COALESCE(NULLIF(lp.Tags, ''), '<none>') AS LatestQuestionTags,
        ta.TagName,
        ta.TaggedQuestionCount,
        ta.PositiveScoreCount,
        ROUND(ta.AvgViews, 2)              AS AvgViewsPerTaggedQuestion,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tu.Id) AS TotalBadges
    FROM TopUsers tu
    LEFT JOIN LatestPosts lp
           ON lp.UserId = tu.Id AND lp.seq = 1
    LEFT JOIN TagAnalytics ta
           ON lp.Tags IS NOT NULL AND POSITION('<' || ta.TagName || '>' IN lp.Tags) > 0
    WHERE tu.rn <= 100
    GROUP BY
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.UpVoteCount,
        tu.DownVoteCount,
        lp.Title,
        lp.CreationDate,
        lp.Tags,
        ta.TagName,
        ta.TaggedQuestionCount,
        ta.PositiveScoreCount,
        ta.AvgViews,
        tu.rn
),
Unioned AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        QuestionCount,
        AnswerCount,
        UpVoteCount,
        DownVoteCount,
        LatestQuestionTitle,
        LatestQuestionDate,
        LatestQuestionTags,
        TagName,
        TaggedQuestionCount,
        PositiveScoreCount,
        AvgViewsPerTaggedQuestion,
        TotalBadges
    FROM Combined
    UNION ALL
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        0 AS QuestionCount,
        0 AS AnswerCount,
        0 AS UpVoteCount,
        0 AS DownVoteCount,
        NULL AS LatestQuestionTitle,
        NULL AS LatestQuestionDate,
        NULL AS LatestQuestionTags,
        NULL AS TagName,
        NULL AS TaggedQuestionCount,
        NULL AS PositiveScoreCount,
        NULL AS AvgViewsPerTaggedQuestion,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS TotalBadges
    FROM Users u
    WHERE u.Id NOT IN (SELECT Id FROM TopUsers)
      AND u.Reputation BETWEEN 1000 AND 2000
)
SELECT *
FROM Unioned
ORDER BY Reputation DESC, (QuestionCount + AnswerCount) DESC;