-- {"query": "34073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1025} 
WITH TopTags AS (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
           p.Id AS PostId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           u.Id AS UserId,
           u.Reputation,
           u.CreationDate AS UserCreationDate,
           u.DisplayName
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
TagAggregates AS (
    SELECT
        Tag,
        COUNT(PostId) AS QuestionCount,
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViewCount,
        AVG(AnswerCount) AS AvgAnswerCount
    FROM TopTags
    GROUP BY Tag
    HAVING COUNT(PostId) > 100
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopUsersPerTag AS (
    SELECT
        tt.Tag,
        tt.UserId,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        COUNT(tt.PostId) AS QuestionsPosted,
        AVG(tt.Score) AS AvgPostScore,
        AVG(VoteScore.UpVotes) AS AvgUpvotes,
        AVG(VoteScore.DownVotes) AS AvgDownvotes
    FROM TopTags tt
    JOIN Users u ON u.Id = tt.UserId
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        WHERE p.PostTypeId IN (1,2)
        GROUP BY p.OwnerUserId
    ) VoteScore ON VoteScore.OwnerUserId = u.Id
    GROUP BY tt.Tag, tt.UserId, u.DisplayName, u.Reputation, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges
),
TopQuestionsWithAcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        u.DisplayName AS AnswerOwner,
        au.Reputation AS AnswerOwnerReputation
    FROM Posts q
    JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.PostTypeId = 2
    JOIN Users u ON u.Id = a.OwnerUserId
    JOIN Users au ON au.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
      AND q.Score > 10
      AND q.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
)
SELECT
    ta.Tag,
    ta.QuestionCount,
    ta.AvgScore,
    ta.AvgViewCount,
    ta.AvgAnswerCount,
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionsPosted,
    tu.AvgPostScore,
    tu.AvgUpvotes,
    tu.AvgDownvotes,
    q.QuestionId,
    q.Title,
    q.CreationDate AS QuestionDate,
    q.QuestionScore,
    q.AnswerId,
    q.AnswerCreationDate,
    q.AnswerScore,
    q.AnswerOwner,
    q.AnswerOwnerReputation
FROM TagAggregates ta
JOIN TopUsersPerTag tu ON tu.Tag = ta.Tag
LEFT JOIN TopQuestionsWithAcceptedAnswers q ON q.QuestionId = (
    SELECT Id FROM Posts
    WHERE PostTypeId = 1
      AND Tags LIKE '%' || '<' || ta.Tag || '>' || '%'
      AND Score = (SELECT MAX(Score) FROM Posts p2 WHERE p2.PostTypeId = 1 AND p2.Tags LIKE '%' || '<' || ta.Tag || '>' || '%')
    LIMIT 1
)
ORDER BY ta.QuestionCount DESC, tu.Reputation DESC, q.QuestionScore DESC
LIMIT 100;