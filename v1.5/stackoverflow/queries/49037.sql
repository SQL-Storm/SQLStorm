-- {"query": "49037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2181} 
WITH TaggedPosts AS (
    -- Parse tags from posts for questions in selected high-activity domains
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        TRIM(UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName
    FROM Posts AS p
    WHERE
        p.PostTypeId = 1 -- Only Questions
        AND p.Tags IS NOT NULL
        AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<python>%' OR p.Tags LIKE '%<javascript>%' OR p.Tags LIKE '%<c#>%' OR p.Tags LIKE '%<java>%')
        AND p.ViewCount >= 5000 -- Focus on questions with significant traffic
        AND p.Score >= 15       -- Focus on well-regarded questions
        AND p.CreationDate >= '2020-01-01' -- Consider questions from recent years
),
PopularTaggedQuestions AS (
    -- Filter for truly popular questions based on parsed tags
    SELECT
        tp.PostId AS QuestionId,
        tp.OwnerUserId AS QuestionOwnerId,
        tp.AcceptedAnswerId,
        tp.TagName
    FROM TaggedPosts AS tp
    WHERE
        tp.AcceptedAnswerId IS NOT NULL
),
AcceptedAnswersSummary AS (
    -- Identify accepted answers to these popular questions and their authors
    SELECT
        ptq.QuestionId,
        ptq.TagName,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswererId,
        a.Score AS AnswerScore,
        u_ans.Reputation AS AnswererReputation
    FROM PopularTaggedQuestions AS ptq
    JOIN Posts AS a ON ptq.AcceptedAnswerId = a.Id
    JOIN Users AS u_ans ON a.OwnerUserId = u_ans.Id
    WHERE
        a.PostTypeId = 2 -- Ensure it's an answer
        AND a.CreationDate >= '2020-01-01' -- Accepted answers should also be recent
),
UserTagAcceptanceCounts AS (
    -- Count accepted answers per user per specific tag and total score from them
    SELECT
        aas.AnswererId AS UserId,
        aas.TagName,
        COUNT(DISTINCT aas.QuestionId) AS AcceptedAnswersCount,
        SUM(aas.AnswerScore) AS TotalAnswerScore
    FROM AcceptedAnswersSummary AS aas
    GROUP BY
        aas.AnswererId,
        aas.TagName
    HAVING
        COUNT(DISTINCT aas.QuestionId) >= 3 -- Users with at least 3 accepted answers in a specific popular tag
),
UserBadgeSummary AS (
    -- Summarize user gold/silver tag-based badges
    SELECT
        b.UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldTagBadgesCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverTagBadgesCount
    FROM Badges AS b
    WHERE
        b.TagBased = TRUE
        AND b.Class IN (1, 2) -- Gold (1) or Silver (2) badges
    GROUP BY
        b.UserId
    HAVING
        COUNT(b.Id) >= 1 -- At least one gold or silver tag badge
),
UserModerationActivity AS (
    -- Identify users who actively participate in closing questions (a form of community moderation)
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS QuestionsClosedCount
    FROM PostHistory AS ph
    WHERE
        ph.PostHistoryTypeId = 10 -- 'Post Closed' event
        AND ph.UserId IS NOT NULL
        AND ph.CreationDate >= '2021-01-01' -- Focus on recent moderation efforts
    GROUP BY
        ph.UserId
    HAVING
        COUNT(DISTINCT ph.PostId) >= 5 -- Users who have helped close at least 5 questions
),
UserOverallMetrics AS (
    -- Calculate aggregated metrics for each user
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswersPosted,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionScore,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.Reputation, u.UpVotes, u.DownVotes
)
-- Final aggregation and ranking of "Expert" users
SELECT
    u.DisplayName,
    uom.Reputation,
    uom.UpVotes,
    uom.DownVotes,
    uom.TotalQuestionsPosted,
    uom.TotalAnswersPosted,
    COALESCE(SUM(utac.AcceptedAnswersCount), 0) AS TotalAcceptedAnswersOnPopularQuestions,
    COALESCE(SUM(utac.TotalAnswerScore), 0) AS AggregateScoreFromAcceptedAnswers,
    COALESCE(ubs.GoldTagBadgesCount, 0) AS GoldTagBadges,
    COALESCE(ubs.SilverTagBadgesCount, 0) AS SilverTagBadges,
    COALESCE(uma.QuestionsClosedCount, 0) AS RecentModerationClosures,
    (
        (uom.Reputation / 1000.0) * 0.3 +                                   -- Reputation contribution (higher impact)
        (COALESCE(SUM(utac.AcceptedAnswersCount), 0) * 5.0) * 0.25 +       -- Accepted answers on popular questions (significant impact)
        (COALESCE(SUM(utac.TotalAnswerScore), 0) / 100.0) * 0.15 +         -- Total score from accepted answers
        (COALESCE(ubs.GoldTagBadgesCount, 0) * 20.0) * 0.1 +               -- Gold badges for expertise recognition
        (COALESCE(ubs.SilverTagBadgesCount, 0) * 5.0) * 0.05 +             -- Silver badges
        (COALESCE(uma.QuestionsClosedCount, 0) * 10.0) * 0.05 +            -- Moderation activity (community contribution)
        ((uom.UpVotes - uom.DownVotes) / 500.0) * 0.1                      -- Net upvotes as a general quality indicator
    ) AS CompositeExpertScore,
    RANK() OVER (ORDER BY (
        (uom.Reputation / 1000.0) * 0.3 +
        (COALESCE(SUM(utac.AcceptedAnswersCount), 0) * 5.0) * 0.25 +
        (COALESCE(SUM(utac.TotalAnswerScore), 0) / 100.0) * 0.15 +
        (COALESCE(ubs.GoldTagBadgesCount, 0) * 20.0) * 0.1 +
        (COALESCE(ubs.SilverTagBadgesCount, 0) * 5.0) * 0.05 +
        (COALESCE(uma.QuestionsClosedCount, 0) * 10.0) * 0.05 +
        ((uom.UpVotes - uom.DownVotes) / 500.0) * 0.1
    ) DESC) AS ExpertRank
FROM Users AS u
JOIN UserOverallMetrics AS uom ON u.Id = uom.UserId
LEFT JOIN UserTagAcceptanceCounts AS utac ON u.Id = utac.UserId
LEFT JOIN UserBadgeSummary AS ubs ON u.Id = ubs.UserId
LEFT JOIN UserModerationActivity AS uma ON u.Id = uma.UserId
WHERE
    uom.Reputation >= 20000 -- Filter for significantly reputable users
    AND (
        utac.UserId IS NOT NULL OR -- Must have accepted answers on popular questions
        ubs.UserId IS NOT NULL OR  -- OR have gold/silver tag badges
        uma.UserId IS NOT NULL     -- OR actively participate in moderation
    )
GROUP BY
    u.Id, u.DisplayName, uom.Reputation, uom.UpVotes, uom.DownVotes,
    uom.TotalQuestionsPosted, uom.TotalAnswersPosted,
    ubs.GoldTagBadgesCount, ubs.SilverTagBadgesCount, uma.QuestionsClosedCount
HAVING
    COALESCE(SUM(utac.AcceptedAnswersCount), 0) > 0 OR
    COALESCE(ubs.GoldTagBadgesCount, 0) > 0 OR
    COALESCE(ubs.SilverTagBadgesCount, 0) > 0 OR
    COALESCE(uma.QuestionsClosedCount, 0) > 0
ORDER BY
    CompositeExpertScore DESC
LIMIT 100;