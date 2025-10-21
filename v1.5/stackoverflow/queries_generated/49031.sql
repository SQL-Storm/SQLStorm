-- {"query": "49031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1108} 

WITH GoldBadgeUsers AS (
    -- Identify users who have at least one gold badge
    SELECT DISTINCT UserId
    FROM Badges
    WHERE Class = 1
),
UserQuestionImpact AS (
    -- Calculate impact metrics for questions by users with Gold Badges
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT ph_body.Id) AS BodyEditCount, -- Specific body edit history
        COUNT(DISTINCT ph_tags.Id) AS TagEditCount   -- Specific tag edit history
    FROM Posts p
    JOIN GoldBadgeUsers gbu ON p.OwnerUserId = gbu.UserId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId IN (1, 3) -- Linked or Duplicate posts
    LEFT JOIN PostHistory ph_body ON p.Id = ph_body.PostId AND ph_body.PostHistoryTypeId = 5 -- Edit Body
    LEFT JOIN PostHistory ph_tags ON p.Id = ph_tags.PostId AND ph_tags.PostHistoryTypeId = 6 -- Edit Tags
    WHERE p.PostTypeId = 1 -- Questions
      AND p.CreationDate >= '2019-01-01 00:00:00'
      AND p.CreationDate < '2024-01-01 00:00:00' -- Questions created within a 5-year window
      AND p.Score >= 100
      AND p.ViewCount >= 5000
      AND p.AnswerCount >= 5
      AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- Ensure tags exist and are not just '<>'
    GROUP BY
        p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.Tags
    HAVING COUNT(DISTINCT pl.RelatedPostId) >= 2 -- At least 2 distinct linked/duplicate posts
),
UserAnswerStats AS (
    -- Calculate average answer score for all users who have gold badges
    SELECT
        p.OwnerUserId AS UserId,
        AVG(p.Score) AS AverageAnswerScore
    FROM Posts p
    JOIN GoldBadgeUsers gbu ON p.OwnerUserId = gbu.UserId
    WHERE p.PostTypeId = 2 -- Answers
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserTagFrequency AS (
    -- Determine the most frequent tags for high-impact questions for each user
    SELECT
        q.OwnerUserId AS UserId,
        tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY COUNT(*) DESC, tag) AS rn
    FROM UserQuestionImpact q,
    LATERAL UNNEST(string_to_array(TRIM(BOTH '<>' FROM q.Tags), '><')) AS tag
    WHERE tag IS NOT NULL AND tag != ''
    GROUP BY q.OwnerUserId, tag
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    SUM(uqi.QuestionScore) AS TotalImpactfulQuestionScore,
    COUNT(DISTINCT uqi.PostId) AS NumberOfImpactfulQuestions,
    AVG(uqi.ViewCount) AS AverageQuestionViewCount,
    AVG(uqi.AnswerCount) AS AverageQuestionAnswerCount,
    MAX(uqi.LinkedPostCount) AS MaxQuestionLinkedCount,
    SUM(uqi.BodyEditCount) AS TotalBodyEditsOnImpactfulQuestions,
    SUM(uqi.TagEditCount) AS TotalTagEditsOnImpactfulQuestions,
    COALESCE(uas.AverageAnswerScore, 0.0) AS AvgAnswerScore,
    STRING_AGG(utf.tag || ' (' || utf.TagCount || ')', '; ' ORDER BY utf.TagCount DESC, utf.tag) AS Top5FrequentTags
FROM Users u
JOIN GoldBadgeUsers gbu ON u.Id = gbu.UserId
JOIN UserQuestionImpact uqi ON u.Id = uqi.OwnerUserId
LEFT JOIN UserAnswerStats uas ON u.Id = uas.UserId
LEFT JOIN UserTagFrequency utf ON u.Id = utf.UserId AND utf.rn <= 5 -- Limit to top 5 tags per user
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, uas.AverageAnswerScore
ORDER BY
    TotalImpactfulQuestionScore DESC, u.Reputation DESC, NumberOfImpactfulQuestions DESC
LIMIT 100;
