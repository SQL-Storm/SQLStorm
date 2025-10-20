-- {"query": "19010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2953} 

WITH UserReputationTiers AS (
    -- Classify users into reputation tiers and quintiles
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legendary'
            WHEN u.Reputation >= 25000 THEN 'Guru'
            WHEN u.Reputation >= 5000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 200 THEN 'Active'
            ELSE 'Novice'
        END AS ReputationTier,
        NTILE(5) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationQuintile
    FROM Users u
    WHERE u.CreationDate >= '2015-01-01' -- Focus on users created after a certain date
      AND u.Views > 0 -- Users with at least one view
),
PostContentSources AS (
    -- Combine questions and answers for unified content analysis
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        COALESCE(p.Title, SUBSTRING(p.Body, 1, 150)) AS DisplayTitleOrBodyExcerpt, -- Use body excerpt for answers
        p.Score AS PostScore,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.AnswerCount, -- Only for questions (PostTypeId = 1)
        p.FavoriteCount,
        p.Tags, -- Only for questions (PostTypeId = 1)
        p.Body,
        p.ClosedDate,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostTypeDescription
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' -- Recent posts
      AND p.Score >= 5 -- Minimum score threshold
      AND p.OwnerUserId IS NOT NULL -- Exclude community owned posts (like tag wikis by -1 user)
),
TopPostsByOwner AS (
    -- Rank posts by score and view count for each owner and post type
    SELECT
        pcs.PostId,
        pcs.OwnerUserId,
        pcs.DisplayTitleOrBodyExcerpt,
        pcs.PostScore,
        pcs.ViewCount,
        pcs.PostCreationDate,
        pcs.LastActivityDate,
        pcs.AnswerCount,
        pcs.FavoriteCount,
        pcs.Tags,
        pcs.PostTypeDescription,
        pcs.Body,
        pcs.ClosedDate,
        DENSE_RANK() OVER (PARTITION BY pcs.OwnerUserId, pcs.PostTypeId ORDER BY pcs.PostScore DESC, pcs.ViewCount DESC, pcs.PostCreationDate DESC) AS UserPostRank,
        LAG(pcs.PostScore, 1, 0) OVER (PARTITION BY pcs.OwnerUserId, pcs.PostTypeId ORDER BY pcs.PostCreationDate) AS PreviousPostScore,
        CASE WHEN pcs.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed
    FROM PostContentSources pcs
),
PostActivitySummary AS (
    -- Aggregate history events for posts, including edits and close votes
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteEventCount, -- Post Closed events
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        STRING_AGG(DISTINCT crt.Name, '; ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS ClosureReasonNames,
        STRING_AGG(DISTINCT ph.UserId::text, ', ') FILTER (WHERE ph.PostHistoryTypeId = 10) AS UsersWhoClosed
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment::smallint = crt.Id -- Cast Comment to smallint for CloseReasonId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13) -- Focus on specific history types
      AND ph.CreationDate >= '2020-01-01'
    GROUP BY ph.PostId
),
UserVoteAggregates AS (
    -- Summarize upvotes and downvotes for posts
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Votes v
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY v.PostId
),
UserTagPerformance AS (
    -- Analyze user's performance by tags (for questions)
    SELECT
        tqp.OwnerUserId AS UserId,
        tag_exploded.tag AS TagName,
        COUNT(tqp.PostId) AS QuestionsWithTag,
        SUM(tqp.PostScore) AS TotalTagScore,
        AVG(tqp.PostScore) AS AvgTagScore,
        RANK() OVER (PARTITION BY tqp.OwnerUserId ORDER BY SUM(tqp.PostScore) DESC, COUNT(tqp.PostId) DESC) AS TagRankByUser
    FROM TopPostsByOwner tqp
    CROSS JOIN LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(tqp.Tags, 2, LENGTH(tqp.Tags) - 2), '><')) AS tag) AS tag_exploded
    WHERE tqp.PostTypeDescription = 'Question'
      AND tqp.PostCreationDate >= '2021-01-01'
      AND tqp.Tags IS NOT NULL
      AND LENGTH(TRIM(REPLACE(REPLACE(tqp.Tags, '<', ''), '>', ''))) > 0 -- Ensure tags are meaningful
    GROUP BY tqp.OwnerUserId, tag_exploded.tag
),
DistinctUserBadges AS (
    -- Count unique badges and list their names for each user
    SELECT
        b.UserId,
        COUNT(DISTINCT b.Name) AS UniqueBadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') AS DistinctBadgeNames,
        MAX(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END) AS LatestGoldBadge
    FROM Badges b
    WHERE b.Date >= '2020-01-01'
    GROUP BY b.UserId
)
SELECT
    urt.UserId,
    urt.DisplayName AS UserName,
    urt.Reputation,
    urt.ReputationTier,
    urt.ReputationQuintile,
    tpo.PostId,
    tpo.DisplayTitleOrBodyExcerpt AS PostTitleOrExcerpt,
    tpo.PostTypeDescription,
    tpo.PostScore,
    tpo.ViewCount,
    tpo.AnswerCount,
    tpo.FavoriteCount AS PostBookmarkCount,
    tpo.PostCreationDate,
    tpo.LastActivityDate,
    tpo.IsClosed AS PostIsClosed,
    COALESCE(uva.UpVotesReceived, 0) AS PostUpVotes,
    COALESCE(uva.DownVotesReceived, 0) AS PostDownVotes,
    COALESCE(uva.FavoriteVotes, 0) AS PostFavoriteVotes,
    pas.TotalHistoryEvents AS PostTotalHistoryEvents,
    pas.EditCount AS PostBodyEditCount,
    pas.CloseVoteEventCount AS PostCloseEvents,
    COALESCE(pas.ClosureReasonNames, 'Not Closed') AS PostClosureReasons,
    db.UniqueBadgeCount AS UserUniqueBadgeCount,
    db.DistinctBadgeNames AS UserDistinctBadgesList,
    db.LatestGoldBadge AS UserLatestGoldBadge,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = tpo.PostId AND c.UserId = urt.UserId AND c.CreationDate > (tpo.PostCreationDate - INTERVAL '6 months')) AS UserRecentCommentsOnOwnPost,
    (SELECT COUNT(p2.Id) FROM Posts p2 WHERE p2.OwnerUserId = urt.UserId AND p2.CreationDate > (tpo.PostCreationDate - INTERVAL '1 year') AND p2.Score >= (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.PostTypeId = p2.PostTypeId AND p3.CreationDate > (NOW() - INTERVAL '1 year'))) AS UserHighScorePostsLastYear,
    MAX(CASE WHEN utp.TagRankByUser = 1 THEN utp.TagName ELSE NULL END) AS TopPerformingTag,
    MAX(CASE WHEN utp.TagRankByUser = 1 THEN utp.TotalTagScore ELSE NULL END) AS TopPerformingTagScore,
    SUM(CASE WHEN tpo.PostTypeDescription = 'Question' AND p_ans.AcceptedAnswerId = tpo.PostId THEN 1 ELSE 0 END) OVER (PARTITION BY urt.UserId) AS AcceptedAnswersToThisUsersQuestions,
    AVG(tpo.PostScore) OVER (PARTITION BY urt.ReputationTier, tpo.PostTypeDescription) AS AvgScoreInTierAndType,
    COUNT(tpo.PostId) OVER (PARTITION BY urt.ReputationTier, tpo.PostTypeDescription) AS TotalPostsInTierAndType
FROM UserReputationTiers urt
JOIN TopPostsByOwner tpo ON urt.UserId = tpo.OwnerUserId
LEFT JOIN UserVoteAggregates uva ON tpo.PostId = uva.PostId
LEFT JOIN PostActivitySummary pas ON tpo.PostId = pas.PostId
LEFT JOIN DistinctUserBadges db ON urt.UserId = db.UserId
LEFT JOIN UserTagPerformance utp ON urt.UserId = utp.UserId AND utp.TagRankByUser = 1 -- Only join for the user's top tag
LEFT JOIN Posts p_ans ON tpo.PostTypeDescription = 'Question' AND tpo.PostId = p_ans.ParentId AND p_ans.AcceptedAnswerId = tpo.PostId -- To identify accepted answers to this question
WHERE tpo.UserPostRank <= 3 -- Only consider the top 3 posts by score/view count for each user and post type
  AND (tpo.Tags IS NULL OR LENGTH(TRIM(REPLACE(REPLACE(tpo.Tags, '<', ''), '>', ''))) > 2) -- Ensure tags are substantial if present
  AND (tpo.DisplayTitleOrBodyExcerpt LIKE '%SQL%' OR tpo.Body LIKE '%database%' OR tpo.Body LIKE '%performance%') -- Complicated string search on title/body
  AND (tpo.FavoriteCount IS NULL OR tpo.FavoriteCount > 0 OR tpo.AnswerCount > 0) -- NULL logic: Favorited or has answers, or no favorites implies no-one favorited
  AND (pas.EditCount IS NULL OR pas.EditCount < 5) -- Filter out excessively edited posts (or those with no edits)
GROUP BY
    urt.UserId, urt.DisplayName, urt.Reputation, urt.ReputationTier, urt.ReputationQuintile, urt.UserCreationDate, urt.LastAccessDate,
    tpo.PostId, tpo.DisplayTitleOrBodyExcerpt, tpo.PostTypeDescription, tpo.PostScore, tpo.ViewCount, tpo.AnswerCount, tpo.FavoriteCount,
    tpo.PostCreationDate, tpo.LastActivityDate, tpo.IsClosed, tpo.Body,
    COALESCE(uva.UpVotesReceived, 0), COALESCE(uva.DownVotesReceived, 0), COALESCE(uva.FavoriteVotes, 0),
    pas.TotalHistoryEvents, pas.EditCount, pas.CloseVoteEventCount, COALESCE(pas.ClosureReasonNames, 'Not Closed'),
    db.UniqueBadgeCount, db.DistinctBadgeNames, db.LatestGoldBadge
HAVING SUM(COALESCE(uva.UpVotesReceived, 0)) + SUM(COALESCE(uva.FavoriteVotes, 0)) >= 10 -- User's specific post must have combined upvotes/favorites of at least 10
   AND MAX(urt.LastAccessDate) >= (NOW() - INTERVAL '6 months') -- User must have been active recently
ORDER BY urt.Reputation DESC, tpo.PostScore DESC, tpo.LastActivityDate DESC;
