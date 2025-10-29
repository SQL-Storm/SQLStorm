-- {"query": "3619.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1993}
WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagUsage AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t AS Tag,
        COUNT(*) AS TagFreq
    FROM Posts p,
    LATERAL (
      SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><') AS t
    ) s
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t
),
TopTags AS (
    SELECT 
        tu.UserId,
        string_agg(tu.Tag, ', ') FILTER (WHERE rn <= 3) AS TopTagList
    FROM (
        SELECT 
            tu.UserId,
            tu.Tag,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagFreq DESC, tu.Tag) AS rn
        FROM TagUsage tu
    ) tu
    GROUP BY tu.UserId
),
RecentVotes AS (
    SELECT 
        v.UserId,
        MAX(v.CreationDate) AS LastVoteDate,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
Combined AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.QuestionCount,
        us.AnswerCount,
        COALESCE(us.AvgScore, 0) AS AvgScore,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        tt.TopTagList,
        rv.LastVoteDate,
        rv.UpVotesGiven,
        rv.DownVotesGiven,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalPosts DESC) AS ReputationRank
    FROM UserStats us
    LEFT JOIN TopTags tt       ON tt.UserId = us.Id
    LEFT JOIN RecentVotes rv   ON rv.UserId = us.Id
)

SELECT *
FROM Combined
WHERE ReputationRank <= 100

UNION ALL

SELECT
    CAST(NULL AS bigint) AS Id,
    'Aggregate Summary' AS DisplayName,
    CAST(NULL AS integer) AS Reputation,
    SUM(TotalPosts) AS TotalPosts,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount) AS AnswerCount,
    AVG(AvgScore) AS AvgScore,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    CAST(NULL AS text) AS TopTagList,
    MAX(LastVoteDate) AS LastVoteDate,
    SUM(UpVotesGiven) AS UpVotesGiven,
    SUM(DownVotesGiven) AS DownVotesGiven,
    CAST(NULL AS integer) AS ReputationRank
FROM Combined
WHERE ReputationRank IS NOT NULL

ORDER BY Reputation DESC NULLS LAST
LIMIT 101;