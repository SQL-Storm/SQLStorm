-- {"query": "1902.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4098} 

WITH RecentHighRepUsers AS (
    -- Identifies users with high reputation, recent activity, and a significant number of posts and badges.
    -- Uses INNER JOIN, LEFT JOIN, WHERE clause with date arithmetic, GROUP BY, and HAVING.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users AS u
    INNER JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE
        u.Reputation >= 5000 AND u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
    HAVING
        COUNT(DISTINCT p.Id) >= 50
),
QuestionBase AS (
    -- Gathers fundamental details for questions, including owner and editor display names and reputation.
    -- Uses INNER JOIN and LEFT JOIN for user details.
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.LastActivityDate,
        q.OwnerUserId AS QuestionOwnerId,
        COALESCE(u_owner.DisplayName, q.OwnerDisplayName, 'Community') AS QuestionOwnerDisplayName, -- NULL logic with COALESCE
        q.LastEditorUserId,
        u_editor.DisplayName AS LastEditorDisplayName,
        u_editor.Reputation AS LastEditorReputation,
        q.LastEditDate,
        q.Tags,
        q.ClosedDate,
        q.CommunityOwnedDate,
        q.Body AS QuestionBody,
        q.AcceptedAnswerId
    FROM Posts AS q
    INNER JOIN PostTypes AS pt ON q.PostTypeId = pt.Id AND pt.Id = 1 -- Filter for questions
    LEFT JOIN Users AS u_owner ON q.OwnerUserId = u_owner.Id
    LEFT JOIN Users AS u_editor ON q.LastEditorUserId = u_editor.Id
    WHERE
        q.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
),
QuestionClosureInfo AS (
    -- Extracts closure-related information, including close reason types and whether a question was ever reopened.
    -- Uses LEFT JOIN, a subquery for MAX date, and complex CASE statements for NULL logic and string interpretation.
    SELECT
        qb.QuestionId,
        qb.QuestionCreationDate,
        qb.ClosedDate,
        qb.LastEditDate,
        ph_closed.CreationDate AS ClosureHistoryDate,
        COALESCE(
            crt.Name, -- For new close reasons (101+), assuming Comment is numeric
            CASE
                WHEN ph_closed.Comment IN ('1', '2', '3', '4', '7', '10', '20') THEN -- Old close reasons
                    CASE ph_closed.Comment
                        WHEN '1' THEN 'Exact Duplicate (Old)'
                        WHEN '2' THEN 'Off-topic (Old)'
                        WHEN '3' THEN 'Subjective and argumentative (Old)'
                        WHEN '4' THEN 'Not a real question (Old)'
                        WHEN '7' THEN 'Too localized (Old)'
                        WHEN '10' THEN 'General reference (Old)'
                        WHEN '20' THEN 'Noise or pointless (Old)'
                        ELSE 'Unknown Old Reason'
                    END
                WHEN ph_closed.Comment IS NOT NULL AND LENGTH(ph_closed.Comment) > 0 THEN 'Custom/Other Close Reason'
                ELSE NULL
            END
        ) AS CloseReasonTypeName,
        ph_closed.Comment AS CloseReasonCommentRaw,
        (CASE
            WHEN ph_closed.PostHistoryTypeId = 10 AND ph_closed.Text LIKE '{%"OriginalQuestionIds":[%}' THEN -- Simplified JSON parsing for example
                SUBSTRING(ph_closed.Text, POSITION('"OriginalQuestionIds":[' IN ph_closed.Text) + LENGTH('"OriginalQuestionIds":['),
                           POSITION(']' IN ph_closed.Text) - (POSITION('"OriginalQuestionIds":[' IN ph_closed.Text) + LENGTH('"OriginalQuestionIds":[')))
            ELSE NULL
        END) AS DuplicateOriginalQuestionIds,
        EXISTS (SELECT 1 FROM PostHistory AS phr WHERE phr.PostId = qb.QuestionId AND phr.PostHistoryTypeId = 11) AS WasReopened -- Correlated subquery
    FROM QuestionBase AS qb
    LEFT JOIN PostHistory AS ph_closed ON qb.QuestionId = ph_closed.PostId
        AND ph_closed.PostHistoryTypeId = 10 -- Post Closed event
        AND ph_closed.CreationDate = (SELECT MAX(ph_sub.CreationDate) FROM PostHistory AS ph_sub WHERE ph_sub.PostId = qb.QuestionId AND ph_sub.PostHistoryTypeId = 10) -- Latest close event
    LEFT JOIN CloseReasonTypes AS crt ON
        (CASE WHEN ph_closed.Comment ~ '^[0-9]+$' THEN CAST(ph_closed.Comment AS smallint) ELSE NULL END) = crt.Id -- Attempt cast only if numeric
),
AnswerAggregates AS (
    -- Aggregates metrics for answers related to questions, including whether the owner accepted their own answer.
    -- Uses INNER JOIN, GROUP BY, and a correlated subquery for HasSelfAcceptedAnswer.
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AverageAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate,
        COUNT(CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN 1 ELSE NULL END) AS AcceptedAnswersCount,
        MAX(CASE
            WHEN a.Id = qb.AcceptedAnswerId AND a.OwnerUserId = qb.QuestionOwnerId
            THEN 1 ELSE 0
        END) AS HasSelfAcceptedAnswer -- Correlated subquery (accessing qb.AcceptedAnswerId)
    FROM Posts AS a
    INNER JOIN QuestionBase AS qb ON a.ParentId = qb.QuestionId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
PostVoteAggregates AS (
    -- Summarizes various vote counts and bounty amounts for posts.
    -- Uses SUM with CASE, and COALESCE.
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountFromVotes,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyAmount,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes AS v
    WHERE v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
    GROUP BY v.PostId
),
UserActivityRank AS (
    -- Ranks users into deciles based on their total upvotes and downvotes.
    -- Uses NTILE window function.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        (u.UpVotes + u.DownVotes) AS TotalVoteActivity,
        NTILE(10) OVER (ORDER BY (u.UpVotes + u.DownVotes) DESC) AS VoteActivityDecile
    FROM Users AS u
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '5 years'
),
BadgeSummary AS (
    -- Provides a summary of user badges, including a "badge class score" and aggregated badge names.
    -- Uses STRING_AGG, SUM with CASE.
    SELECT
        b.UserId,
        COUNT(b.Id) AS UserBadgeCount,
        SUM(CASE b.Class WHEN 1 THEN 3 WHEN 2 THEN 2 WHEN 3 THEN 1 ELSE 0 END) AS BadgeClassScore,
        STRING_AGG(DISTINCT b.Name, '; ' ORDER BY b.Name) AS AllBadges
    FROM Badges AS b
    GROUP BY b.UserId
),
TopQuestionTags AS (
    -- Identifies the most frequently used tags. Non-correlated subquery for tag filtering.
    SELECT
        t.TagName
    FROM Tags AS t
    ORDER BY t.Count DESC
    LIMIT 100
)
-- Main Query 1: Focus on highly active, high-impact, and currently open questions.
SELECT
    qb.QuestionId,
    qb.QuestionTitle,
    qb.QuestionOwnerDisplayName,
    rhu.Reputation AS QuestionOwnerReputation,
    qb.QuestionCreationDate,
    qb.QuestionScore,
    qb.ViewCount,
    qb.AnswerCount,
    aa.TotalAnswers,
    aa.AverageAnswerScore,
    CAST(aa.HasSelfAcceptedAnswer AS BOOLEAN) AS HasSelfAcceptedAnswer, -- Ensure consistent type for UNION ALL
    pva_q.UpVotesCount AS QuestionUpVotes,
    pva_q.DownVotesCount AS QuestionDownVotes,
    pva_q.TotalBountyAmount AS QuestionBountyAmount,
    pva_q.FavoriteCountFromVotes,
    qb.LastEditorDisplayName,
    qb.LastEditorReputation,
    qb.LastEditDate,
    qci.ClosedDate,
    qci.CloseReasonTypeName,
    CAST(qci.WasReopened AS BOOLEAN) AS WasReopened, -- Ensure consistent type for UNION ALL
    -- Complicated string expression for question body excerpt, involving COALESCE and REPLACE
    SUBSTRING(
        COALESCE(
            REPLACE(REPLACE(REPLACE(qb.QuestionBody, '<p>', ''), '</p>', ''), '<code>', ''),
            'No Body Text'
        ), 1, 200
    ) AS QuestionBodyCleanExcerpt,
    -- Window function: Ranks questions by a score adjusted for age in months.
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM qb.QuestionCreationDate) ORDER BY qb.QuestionScore * (1 + EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - qb.QuestionCreationDate)) / (3600 * 24 * 30)) DESC) AS QuestionActivityRank,
    -- Complex calculation: Score per view, adjusted by answer presence and recent activity. Uses GREATEST and CASE.
    (qb.QuestionScore * 1.0 / GREATEST(1, qb.ViewCount)) * (1 + (aa.TotalAnswers * 0.1)) * (CASE WHEN qb.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '3 months' THEN 1.2 ELSE 1 END) AS CalculatedImpactScore,
    -- String array logic: Filters and aggregates tags to show only those present in TopQuestionTags.
    ARRAY_TO_STRING(
        ARRAY(
            SELECT UNNEST_TAG
            FROM UNNEST(string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><')) AS UNNEST_TAG
            WHERE UNNEST_TAG IN (SELECT TagName FROM TopQuestionTags)
        ), ', '
    ) AS RelevantTopTags,
    -- Correlated subquery: Counts owner's tag-based gold badges for question's tags.
    (
        SELECT COUNT(b2.Id)
        FROM Badges AS b2
        INNER JOIN UNNEST(string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><')) AS Q_TAG ON b2.Name = Q_TAG
        WHERE b2.UserId = qb.QuestionOwnerId AND b2.Class = 1 AND b2.TagBased = TRUE
    ) AS OwnerTagBasedSpecificBadges,
    ua.VoteActivityDecile AS QuestionOwnerVoteDecile,
    bs.BadgeClassScore AS QuestionOwnerBadgeScore,
    'Active/High-Impact' AS QueryCategory
FROM QuestionBase AS qb
INNER JOIN AnswerAggregates AS aa ON qb.QuestionId = aa.QuestionId
LEFT JOIN PostVoteAggregates AS pva_q ON qb.QuestionId = pva_q.PostId
LEFT JOIN RecentHighRepUsers AS rhu ON qb.QuestionOwnerId = rhu.UserId
LEFT JOIN QuestionClosureInfo AS qci ON qb.QuestionId = qci.QuestionId
LEFT JOIN UserActivityRank AS ua ON qb.QuestionOwnerId = ua.UserId
LEFT JOIN BadgeSummary AS bs ON qb.QuestionOwnerId = bs.UserId
WHERE
    qb.QuestionScore >= 10
    AND qb.ViewCount >= 500
    AND qb.ClosedDate IS NULL -- Only open questions (NULL logic)
    AND qb.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '6 months' -- Recently active
    AND (qb.Tags ILIKE '%<sql>%' OR qb.Tags ILIKE '%<database>%') -- String expression with ILIKE
    AND aa.TotalAnswers >= 2
    AND aa.AverageAnswerScore >= 5

UNION ALL

-- Main Query 2: Focus on recently closed, but well-engaged questions or questions with many edits.
SELECT
    qb.QuestionId,
    qb.QuestionTitle,
    qb.QuestionOwnerDisplayName,
    rhu.Reputation AS QuestionOwnerReputation,
    qb.QuestionCreationDate,
    qb.QuestionScore,
    qb.ViewCount,
    qb.AnswerCount,
    aa.TotalAnswers,
    aa.AverageAnswerScore,
    CAST(aa.HasSelfAcceptedAnswer AS BOOLEAN) AS HasSelfAcceptedAnswer,
    pva_q.UpVotesCount AS QuestionUpVotes,
    pva_q.DownVotesCount AS QuestionDownVotes,
    pva_q.TotalBountyAmount AS QuestionBountyAmount,
    pva_q.FavoriteCountFromVotes,
    qb.LastEditorDisplayName,
    qb.LastEditorReputation,
    qb.LastEditDate,
    qci.ClosedDate,
    qci.CloseReasonTypeName,
    CAST(qci.WasReopened AS BOOLEAN) AS WasReopened,
    SUBSTRING(
        COALESCE(
            REPLACE(REPLACE(REPLACE(qb.QuestionBody, '<p>', ''), '</p>', ''), '<code>', ''),
            'No Body Text (Closed)'
        ), 1, 200
    ) AS QuestionBodyCleanExcerpt,
    -- Window function: Ranks closed questions by edit date and answer count within their closure year.
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM qb.ClosedDate) ORDER BY qb.LastEditDate DESC, aa.TotalAnswers DESC) AS QuestionActivityRank,
    -- Complex calculation: Score per answer, adjusted by closure recency and editor's reputation.
    (qb.QuestionScore * 1.0 / GREATEST(1, aa.TotalAnswers)) * (CASE WHEN qb.ClosedDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 1.5 ELSE 1 END) * (COALESCE(qb.LastEditorReputation, 0) / 1000.0) AS CalculatedImpactScore,
    ARRAY_TO_STRING(
        ARRAY(
            SELECT UNNEST_TAG
            FROM UNNEST(string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><')) AS UNNEST_TAG
            WHERE LOWER(UNNEST_TAG) LIKE '%security%' OR LOWER(UNNEST_TAG) LIKE '%api%'
        ), ', '
    ) AS RelevantTopTags,
    -- Correlated subquery: Counts owner's silver badges.
    (
        SELECT COUNT(b3.Id)
        FROM Badges AS b3
        WHERE b3.UserId = qb.QuestionOwnerId AND b3.Class = 2
    ) AS OwnerTagBasedSpecificBadges,
    ua.VoteActivityDecile AS QuestionOwnerVoteDecile,
    bs.BadgeClassScore AS QuestionOwnerBadgeScore,
    'Closed/Engaged' AS QueryCategory
FROM QuestionBase AS qb
INNER JOIN AnswerAggregates AS aa ON qb.QuestionId = aa.QuestionId
LEFT JOIN PostVoteAggregates AS pva_q ON qb.QuestionId = pva_q.PostId
LEFT JOIN RecentHighRepUsers AS rhu ON qb.QuestionOwnerId = rhu.UserId
LEFT JOIN QuestionClosureInfo AS qci ON qb.QuestionId = qci.QuestionId
LEFT JOIN UserActivityRank AS ua ON qb.QuestionOwnerId = ua.UserId
LEFT JOIN BadgeSummary AS bs ON qb.QuestionOwnerId = bs.UserId
WHERE
    qb.ClosedDate IS NOT NULL -- Only closed questions (NULL logic)
    AND qb.ClosedDate >= CURRENT_TIMESTAMP - INTERVAL '2 years' -- Closed recently
    AND qb.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' -- Still some activity
    AND aa.TotalAnswers >= 1
    AND (
        (qb.QuestionScore >= 20 AND qb.FavoriteCount >= 5) OR -- Complex predicate with OR
        (qci.WasReopened = TRUE)
    )
ORDER BY
    CalculatedImpactScore DESC,
    QuestionCreationDate DESC
LIMIT 1000;
