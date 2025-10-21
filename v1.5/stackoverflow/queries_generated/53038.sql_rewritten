-- {"query": "53038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 578} 
WITH QuestionTags AS (
    SELECT 
        p.Id AS QuestionId,
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        t.tag AS TagName
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
    WHERE p.PostTypeId = 1
),
PopularTagsPerYear AS (
    SELECT 
        Year,
        TagName,
        COUNT(QuestionId) AS QuestionCount,
        ROW_NUMBER() OVER (PARTITION BY Year ORDER BY COUNT(QuestionId) DESC) AS rn
    FROM QuestionTags
    GROUP BY Year, TagName
),
TopTags AS (
    SELECT Year, TagName, QuestionCount
    FROM PopularTagsPerYear
    WHERE rn = 1
),
AnswerScores AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        qt.Year,
        qt.TagName
    FROM Posts a
    INNER JOIN QuestionTags qt ON a.ParentId = qt.QuestionId
    WHERE a.PostTypeId = 2
),
TopContributors AS (
    SELECT 
        Year,
        TagName,
        OwnerUserId,
        SUM(Score) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY Year, TagName ORDER BY SUM(Score) DESC) AS rn
    FROM AnswerScores
    GROUP BY Year, TagName, OwnerUserId
),
UserDetails AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    tt.Year,
    tt.TagName,
    tt.QuestionCount AS TagQuestionCount,
    tc.OwnerUserId,
    ud.DisplayName,
    ud.Reputation,
    ud.BadgeCount,
    ud.GoldBadges,
    tc.TotalScore AS ContributorScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT a.Id FROM Posts a WHERE a.OwnerUserId = tc.OwnerUserId AND a.PostTypeId = 2) AND v.VoteTypeId = 2) AS TotalUpvotesOnAnswers
FROM TopTags tt
INNER JOIN TopContributors tc ON tt.Year = tc.Year AND tt.TagName = tc.TagName AND tc.rn = 1
INNER JOIN UserDetails ud ON tc.OwnerUserId = ud.UserId
ORDER BY tt.Year DESC, tt.QuestionCount DESC;