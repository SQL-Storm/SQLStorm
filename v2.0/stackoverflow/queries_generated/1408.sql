-- {"query": "1408.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3801} 

WITH UserReputationTiers AS (
    -- Classify users into reputation tiers and calculate their average post score for all posts within their last access year.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        CASE
            WHEN u.Reputation >= 20000 THEN 'Legendary'
            WHEN u.Reputation >= 5000 THEN 'High'
            WHEN u.Reputation >= 1000 THEN 'Medium'
            WHEN u.Reputation >= 100 THEN 'Apprentice'
            ELSE 'Novice'
        END AS ReputationTier,
        COALESCE((SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate >= u.LastAccessDate - INTERVAL '1 year'), 0.0) AS AvgScoreLastYearPosts
    FROM Users u
    WHERE u.DisplayName IS NOT NULL AND u.LastAccessDate IS NOT NULL
),
PostBaseInfo AS (
    -- Extract essential post details, calculate age, body length, and initial tag processing.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Body,
        p.Title,
        p.Tags,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) / (60*60*24) AS PostAgeDays,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.LastEditorUserId, p.OwnerUserId, -1) AS EffectiveEditorId,
        p.LastEditDate,
        p.ClosedDate,
        -- Non-correlated scalar subquery: average score of posts created in the same month as this post (across all users)
        (
            SELECT AVG(sub_p.Score)
            FROM Posts sub_p
            WHERE EXTRACT(YEAR FROM sub_p.CreationDate) = EXTRACT(YEAR FROM p.CreationDate)
              AND EXTRACT(MONTH FROM sub_p.CreationDate) = EXTRACT(MONTH FROM p.CreationDate)
              AND sub_p.PostTypeId = p.PostTypeId
        ) AS AvgMonthlyPostScoreForType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
),
PostExtendedAttributes AS (
    -- Process tags, detect code snippets, and aggregate comment/vote counts.
    SELECT
        pbi.PostId,
        pbi.PostTypeId,
        pbi.OwnerUserId,
        pbi.AcceptedAnswerId,
        pbi.ParentId,
        pbi.CreationDate,
        pbi.Score,
        pbi.ViewCount,
        pbi.Body,
        pbi.Title,
        pbi.PostAgeDays,
        pbi.BodyLength,
        pbi.EffectiveEditorId,
        pbi.LastEditDate,
        pbi.ClosedDate,
        pbi.AvgMonthlyPostScoreForType,
        COALESCE(
            string_to_array(SUBSTRING(pbi.Tags, 2, LENGTH(pbi.Tags)-2), '><'),
            ARRAY[]::varchar[]
        ) AS TagArray,
        CASE
            WHEN pbi.Body LIKE '%<pre><code>%' AND pbi.Body LIKE '%</code></pre>%' THEN TRUE
            ELSE FALSE
        END AS HasCodeSnippet,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = pbi.PostId) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesFromHistory,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesFromHistory,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoritesFromHistory -- Old favorite system
    FROM PostBaseInfo pbi
    LEFT JOIN Votes v ON pbi.PostId = v.PostId AND v.VoteTypeId IN (2, 3, 5)
    GROUP BY
        pbi.Id, pbi.PostTypeId, pbi.OwnerUserId, pbi.AcceptedAnswerId, pbi.ParentId,
        pbi.CreationDate, pbi.Score, pbi.ViewCount, pbi.Body, pbi.Title, pbi.Tags,
        pbi.PostAgeDays, pbi.BodyLength, pbi.EffectiveEditorId, pbi.LastEditDate,
        pbi.ClosedDate, pbi.AvgMonthlyPostScoreForType
),
PostEditAndLinkMetrics AS (
    -- Calculate edit frequency and link influence (duplicates and linked posts).
    SELECT
        pea.PostId,
        pea.PostTypeId,
        pea.OwnerUserId,
        pea.AcceptedAnswerId,
        pea.ParentId,
        pea.CreationDate,
        pea.Score,
        pea.ViewCount,
        pea.Body,
        pea.Title,
        pea.PostAgeDays,
        pea.BodyLength,
        pea.EffectiveEditorId,
        pea.LastEditDate,
        pea.ClosedDate,
        pea.AvgMonthlyPostScoreForType,
        pea.TagArray,
        pea.HasCodeSnippet,
        pea.CommentCount,
        pea.UpVotesFromHistory,
        pea.DownVotesFromHistory,
        pea.FavoritesFromHistory,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)) AS EditHistoryEntryCount,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutgoingLinksCount, -- Linked
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount, -- Duplicate
        -- Correlated subquery: check if any close reason was 'Off-topic' for this post
        EXISTS (
            SELECT 1 FROM PostHistory sub_ph
            WHERE sub_ph.PostId = pea.PostId
              AND sub_ph.PostHistoryTypeId = 10 -- Post Closed
              AND COALESCE(sub_ph.Comment, '') IN ('2', '102') -- Old/New Off-topic close reason IDs
        ) AS WasClosedAsOffTopic
    FROM PostExtendedAttributes pea
    LEFT JOIN PostHistory ph ON pea.PostId = ph.PostId
    LEFT JOIN PostLinks pl ON pea.PostId = pl.PostId
    GROUP BY
        pea.PostId, pea.PostTypeId, pea.OwnerUserId, pea.AcceptedAnswerId, pea.ParentId,
        pea.CreationDate, pea.Score, pea.ViewCount, pea.Body, pea.Title,
        pea.PostAgeDays, pea.BodyLength, pea.EffectiveEditorId, pea.LastEditDate,
        pea.ClosedDate, pea.AvgMonthlyPostScoreForType, pea.TagArray,
        pea.HasCodeSnippet, pea.CommentCount, pea.UpVotesFromHistory, pea.DownVotesFromHistory,
        pea.FavoritesFromHistory
),
FinalPostScores AS (
    -- Apply window functions for ranking and percentile.
    SELECT
        pelm.PostId,
        pelm.PostTypeId,
        pelm.OwnerUserId,
        pelm.AcceptedAnswerId,
        pelm.ParentId,
        pelm.CreationDate,
        pelm.Score,
        pelm.ViewCount,
        pelm.Body,
        pelm.Title,
        pelm.PostAgeDays,
        pelm.BodyLength,
        pelm.EffectiveEditorId,
        pelm.LastEditDate,
        pelm.ClosedDate,
        pelm.AvgMonthlyPostScoreForType,
        pelm.TagArray,
        pelm.HasCodeSnippet,
        pelm.CommentCount,
        pelm.UpVotesFromHistory,
        pelm.DownVotesFromHistory,
        pelm.FavoritesFromHistory,
        pelm.EditHistoryEntryCount,
        pelm.OutgoingLinksCount,
        pelm.DuplicateLinksCount,
        pelm.WasClosedAsOffTopic,
        -- Window functions:
        -- Rank posts by score within each post type, ordered by creation date descending
        RANK() OVER (PARTITION BY pelm.PostTypeId ORDER BY pelm.Score DESC, pelm.CreationDate DESC) AS ScoreRankByType,
        -- Calculate the cumulative distribution of views within a specific time frame
        CUME_DIST() OVER (ORDER BY pelm.ViewCount) AS ViewCountCumeDist,
        -- Get the next post's creation date by the same owner
        LEAD(pelm.CreationDate, 1) OVER (PARTITION BY pelm.OwnerUserId ORDER BY pelm.CreationDate) AS NextPostCreationDateByOwner,
        -- Calculate rolling average score for posts by the same owner over a 3-post window
        AVG(pelm.Score) OVER (PARTITION BY pelm.OwnerUserId ORDER BY pelm.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgOwnerScore
    FROM PostEditAndLinkMetrics pelm
    WHERE pelm.Score > 0 -- Only consider posts with positive score
)
-- Main Query combining all information with UNION ALL for distinct analysis branches
SELECT
    'Question' AS PostCategory,
    fps.PostId,
    fps.Title,
    urt.DisplayName AS OwnerDisplayName,
    urt.ReputationTier,
    fps.CreationDate,
    fps.Score,
    fps.ViewCount,
    fps.PostAgeDays,
    fps.BodyLength,
    fps.CommentCount,
    fps.UpVotesFromHistory AS UpVotesTotal,
    fps.DownVotesFromHistory AS DownVotesTotal,
    fps.FavoritesFromHistory AS FavoritesTotal,
    fps.OutgoingLinksCount,
    fps.DuplicateLinksCount,
    fps.HasCodeSnippet,
    fps.EditHistoryEntryCount,
    fps.AvgMonthlyPostScoreForType,
    fps.ScoreRankByType,
    fps.ViewCountCumeDist,
    fps.NextPostCreationDateByOwner,
    fps.RollingAvgOwnerScore,
    ARRAY_LENGTH(fps.TagArray, 1) AS NumberOfTags,
    COALESCE(
        fps.UpVotesFromHistory * 1.0 / NULLIF(fps.UpVotesFromHistory + fps.DownVotesFromHistory, 0),
        0.0
    ) AS UpVoteRatio,
    -- Determine if the question has an accepted answer and its age relative to post creation
    CASE
        WHEN fps.AcceptedAnswerId IS NOT NULL THEN
            'Accepted: ' ||
            COALESCE(
                EXTRACT(EPOCH FROM (
                    (SELECT sub_ans.CreationDate FROM Posts sub_ans WHERE sub_ans.Id = fps.AcceptedAnswerId) - fps.CreationDate
                )) / (60*60*24) || ' days',
                'Unknown Age'
            )
        WHEN fps.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS AcceptanceAndStatusDetail,
    fps.WasClosedAsOffTopic,
    -- Correlated subquery to find average score of questions linked to this one
    COALESCE((
        SELECT AVG(pl_related.Score)
        FROM PostLinks pl_link
        JOIN Posts pl_related ON pl_link.RelatedPostId = pl_related.Id
        WHERE pl_link.PostId = fps.PostId
          AND pl_related.PostTypeId = 1
    ), 0.0) AS AvgLinkedQuestionScore,
    COALESCE(urt.AvgScoreLastYearPosts, 0.0) AS OwnerAvgScoreLastYear,
    NULLIF(LENGTH(REPLACE(fps.Body, ' ', '')), 0) AS NonSpaceBodyLength
FROM FinalPostScores fps
INNER JOIN UserReputationTiers urt ON fps.OwnerUserId = urt.UserId
WHERE fps.PostTypeId = 1 -- Only questions for this branch
  AND fps.Score > fps.AvgMonthlyPostScoreForType * 1.5 -- Score significantly higher than monthly average for its type
  AND fps.ViewCount > 1000
  AND fps.PostAgeDays < 730 -- Active within two years
  AND fps.BodyLength > 200
  AND fps.Title IS NOT NULL AND fps.Title LIKE '%[a-zA-Z]%' -- Title exists and has letters
  AND ARRAY_LENGTH(fps.TagArray, 1) >= 2 -- At least two tags
  AND NOT EXISTS (
      SELECT 1 FROM Comments c
      WHERE c.PostId = fps.PostId
        AND c.Text ILIKE '%please provide more details%'
        AND c.CreationDate > fps.CreationDate
  ) -- Question does not have a "needs more details" comment after creation
  AND fps.HasCodeSnippet
  AND urt.ReputationTier IN ('Legendary', 'High')
  AND (fps.UpVotesFromHistory + fps.DownVotesFromHistory) > 10 -- Minimum vote activity

UNION ALL

SELECT
    'Answer' AS PostCategory,
    fps.PostId,
    fps.Title, -- Title is NULL for answers, demonstrating NULL display
    urt.DisplayName AS OwnerDisplayName,
    urt.ReputationTier,
    fps.CreationDate,
    fps.Score,
    fps.ViewCount,
    fps.PostAgeDays,
    fps.BodyLength,
    fps.CommentCount,
    fps.UpVotesFromHistory AS UpVotesTotal,
    fps.DownVotesFromHistory AS DownVotesTotal,
    fps.FavoritesFromHistory AS FavoritesTotal,
    fps.OutgoingLinksCount,
    fps.DuplicateLinksCount,
    fps.HasCodeSnippet,
    fps.EditHistoryEntryCount,
    fps.AvgMonthlyPostScoreForType,
    fps.ScoreRankByType,
    fps.ViewCountCumeDist,
    fps.NextPostCreationDateByOwner,
    fps.RollingAvgOwnerScore,
    ARRAY_LENGTH(fps.TagArray, 1) AS NumberOfTags,
    COALESCE(
        fps.UpVotesFromHistory * 1.0 / NULLIF(fps.UpVotesFromHistory + fps.DownVotesFromHistory, 0),
        0.0
    ) AS UpVoteRatio,
    -- Check if this answer is accepted for its parent question
    CASE
        WHEN fps.PostId = (SELECT q.AcceptedAnswerId FROM Posts q WHERE q.Id = fps.ParentId) THEN 'Accepted Answer'
        ELSE 'Not Accepted'
    END AS AcceptanceAndStatusDetail,
    FALSE AS WasClosedAsOffTopic, -- Not applicable for answers
    COALESCE((
        SELECT AVG(c.Score)
        FROM Comments c
        WHERE c.PostId = fps.PostId
    ), 0.0) AS AvgCommentScore, -- Correlated subquery for answer comments
    COALESCE(urt.AvgScoreLastYearPosts, 0.0) AS OwnerAvgScoreLastYear,
    NULLIF(LENGTH(REPLACE(fps.Body, ' ', '')), 0) AS NonSpaceBodyLength
FROM FinalPostScores fps
INNER JOIN UserReputationTiers urt ON fps.OwnerUserId = urt.UserId
WHERE fps.PostTypeId = 2 -- Only answers for this branch
  AND fps.Score >= 5 -- Only well-received answers
  AND fps.BodyLength > 150
  AND fps.CommentCount >= 1
  AND fps.CreationDate >= '2022-01-01' -- Relatively recent answers
  AND urt.ReputationTier IN ('High', 'Medium')
  AND (
      (fps.HasCodeSnippet AND fps.EditHistoryEntryCount > 0) OR -- Code snippet answers that have been edited
      (fps.UpVotesFromHistory > fps.DownVotesFromHistory * 2)    -- Or answers with significantly more upvotes
  )
  AND NOT EXISTS (
      SELECT 1 FROM Badges b
      WHERE b.UserId = urt.UserId
        AND b.Name ILIKE '%critic%'
  ) -- Exclude answers from users with a "Critic" badge (frequent downvoter)
ORDER BY CreationDate DESC, Score DESC, ReputationTier;
