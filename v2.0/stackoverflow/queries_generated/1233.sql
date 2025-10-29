-- {"query": "1233.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2327} 

WITH UserPostStats AS (
    -- Aggregate overall post statistics and distinct tags for each user
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        MAX(p.CreationDate) AS LatestPostCreation,
        MIN(p.CreationDate) AS EarliestPostCreation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        -- Aggregate distinct tags from questions using a LATERAL join for string parsing
        STRING_AGG(DISTINCT t.Tag, '><') AS AllUniqueQuestionTagsConcat,
        COUNT(DISTINCT t.Tag) AS DistinctQuestionTagCount
    FROM Posts p
    LEFT JOIN LATERAL UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t(Tag) ON p.PostTypeId = 1 AND p.Tags IS NOT NULL
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
HighlyVotedAnswers AS (
    -- Identify answers that have received a significant number of upvotes and find their parent questions
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswerOwnerId,
        p.Score AS AnswerScore,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount, -- VoteType 2 is UpMod
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2 -- Only answers
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.ParentId, p.OwnerUserId, p.Score
    HAVING COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) >= 20 -- At least 20 upvotes
),
ClosedDuplicateQuestions AS (
    -- Identify questions that were officially closed as duplicates
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        ph.CreationDate AS ClosureDate,
        cr.Name AS CloseReasonName,
        ph.Text AS DuplicateInfo -- JSON string with original question IDs if applicable
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    JOIN CloseReasonTypes cr ON ph.Comment::smallint = cr.Id -- Cast comment to smallint for join
    WHERE p.PostTypeId = 1 -- Only questions
      AND ph.PostHistoryTypeId = 10 -- Post Closed
      AND cr.Id IN (1, 101) -- Old (Exact Duplicate) or New (Duplicate) reasons
),
UserBadgeSummary AS (
    -- Summarize user badges, counting different classes (Gold, Silver, Bronze)
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserOverallAnswerVotes AS (
    -- Aggregate total upvotes and downvotes for ALL answers contributed by a user
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswerUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalAnswerDownvotes
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2 -- Only answers
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
-- Main query to analyze user performance, contributions, and community standing
SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Unknown User ' || u.Id) AS UserDisplayName,
    u.Reputation,
    u.CreationDate AS UserAccountCreationDate,
    u.LastAccessDate,
    COALESCE(ups.TotalPosts, 0) AS TotalPosts,
    COALESCE(ups.QuestionsCount, 0) AS QuestionsCount,
    COALESCE(ups.AnswersCount, 0) AS AnswersCount,
    COALESCE(ups.AvgQuestionViewCount, 0) AS AvgQuestionViewCount,
    COALESCE(ups.DistinctQuestionTagCount, 0) AS DistinctQuestionTagsUsed,
    COALESCE(usb.GoldBadges, 0) AS GoldBadges,
    COALESCE(usb.SilverBadges, 0) AS SilverBadges,
    COALESCE(usb.BronzeBadges, 0) AS BronzeBadges,
    -- Correlated subquery: Calculate average score of their highly voted answers (with higher upvote threshold)
    (SELECT AVG(hva_sub.AnswerScore)
     FROM HighlyVotedAnswers hva_sub
     WHERE hva_sub.AnswerOwnerId = u.Id
       AND hva_sub.UpvoteCount >= 50
    ) AS AvgEliteAnswerScore,
    -- Correlated subquery: Check if the user has questions that were closed as duplicates
    EXISTS (
        SELECT 1
        FROM ClosedDuplicateQuestions cdq
        WHERE cdq.QuestionOwnerId = u.Id
    ) AS HasAskedDuplicateQuestions,
    -- Correlated subquery: Count how many of their answers have been accepted by others
    (SELECT COUNT(DISTINCT p_accepted.Id)
     FROM Posts p_accepted
     WHERE p_accepted.PostTypeId = 2
       AND p_accepted.OwnerUserId = u.Id
       AND p_accepted.Id = (SELECT p_q.AcceptedAnswerId FROM Posts p_q WHERE p_q.Id = p_accepted.ParentId AND p_q.AcceptedAnswerId IS NOT NULL)
    ) AS AcceptedAnswersCount,
    -- Window function: Rank users based on their total post score within their account creation year
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY ups.TotalPostScore DESC NULLS LAST, u.Reputation DESC) AS RankByTotalPostScoreInYear,
    -- Complex string manipulation and NULL logic for user's profile summary
    SUBSTRING(u.WebsiteUrl, POSITION('//' IN u.WebsiteUrl) + 2, LENGTH(u.WebsiteUrl)) AS CleanedWebsiteUrl,
    LOWER(LEFT(TRIM(COALESCE(u.Location, 'N/A Location')), 10)) || '_' ||
    CASE
        WHEN LENGTH(COALESCE(u.AboutMe, '')) > 500 THEN 'VeryVerbose'
        WHEN LENGTH(COALESCE(u.AboutMe, '')) > 100 THEN 'Verbose'
        WHEN LENGTH(COALESCE(u.AboutMe, '')) > 0 THEN 'Concise'
        ELSE 'NoAboutMe'
    END AS ProfileDetailSummary,
    -- Categorize users based on multiple criteria, including existence checks and complex logic
    CASE
        WHEN COALESCE(usb.GoldBadges, 0) >= 5 AND COALESCE(ups.QuestionsCount, 0) >= 10 AND COALESCE(ups.AnswersCount, 0) >= 20 THEN 'Seasoned Expert'
        WHEN COALESCE(usb.GoldBadges, 0) >= 1 AND EXISTS (SELECT 1 FROM HighlyVotedAnswers hva WHERE hva.AnswerOwnerId = u.Id AND hva.AnswerScore > 200) THEN 'Influential Answerer'
        WHEN EXISTS (SELECT 1 FROM ClosedDuplicateQuestions cdq WHERE cdq.QuestionOwnerId = u.Id) AND COALESCE(usb.GoldBadges, 0) = 0 THEN 'NeedsGuidance'
        WHEN u.Reputation > 10000 AND (CURRENT_DATE - u.LastAccessDate) < INTERVAL '3 months' THEN 'Active High-Rep User'
        ELSE 'General Contributor'
    END AS UserPersonaClassification,
    -- Calculate ratio of positive to negative votes received on their answers using NULL logic
    CAST(COALESCE(uoav.TotalAnswerUpvotes, 0) AS NUMERIC) / NULLIF(COALESCE(uoav.TotalAnswerUpvotes, 0) + COALESCE(uoav.TotalAnswerDownvotes, 0), 0) AS AnswerVoteSuccessRatio
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserBadgeSummary usb ON u.Id = usb.UserId
LEFT JOIN UserOverallAnswerVotes uoav ON u.Id = uoav.UserId
WHERE u.Reputation >= 500 -- Filter for users with a minimum reputation
  AND u.CreationDate >= '2015-01-01' -- Limit date range to a specific cohort
  AND u.LastAccessDate IS NOT NULL -- Exclude users without a recorded last access
  AND (u.DisplayName IS NOT NULL OR u.AccountId IS NOT NULL) -- Ensure user has some form of identification
  AND NOT EXISTS ( -- Anti-correlated subquery: user has not posted any extremely short comments in the last 6 months
      SELECT 1 FROM Comments c
      WHERE c.UserId = u.Id
        AND c.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '6 months')
        AND LENGTH(c.Text) < 10
  )
HAVING COALESCE(ups.TotalPosts, 0) >= 5 -- Final filter: only include users with at least 5 posts total
ORDER BY RankByTotalPostScoreInYear ASC, u.Reputation DESC
LIMIT 500;
