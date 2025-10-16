-- {"query": "1579.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1831} 
WITH RecursiveBadgeCount AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
), PostStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Title,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags, '') AS Tags,
        COALESCE(u.DisplayName, 'Unknown') AS OwnerDisplayName,
        phc.CloseReasonId,
        phc.PostClosedDate
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            MAX(CASE WHEN PostHistoryTypeId = 10 THEN CreatedCloseDate END) AS PostClosedDate,
            MAX(CASE WHEN PostHistoryTypeId = 10 THEN CAST(Comment AS INT) END) AS CloseReasonId
        FROM (
            SELECT 
                PostId,
                PostHistoryTypeId,
                Comment,
                CreationDate AS CreatedCloseDate
            FROM PostHistory
            WHERE PostHistoryTypeId = 10
        ) closings
        GROUP BY PostId
    ) phc ON phc.PostId = p.Id
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
), TagExploded AS (
    SELECT
        ps.Id AS PostId,
        unnest(string_to_array(substring(ps.Tags, 2, length(ps.Tags) - 2), '><')) AS Tag
    FROM PostStats ps
    WHERE ps.PostTypeId = 1 AND ps.Tags != ''
), UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesCast,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesCast,
        COUNT(DISTINCT v.PostId) AS UniquePostsVotedOn
    FROM Votes v
    INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
), TopAnswersPerQuestion AS (
    SELECT DISTINCT ON (a.ParentId)
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.CreationDate,
        a.Score
    FROM Posts a
    WHERE a.PostTypeId = 2
    ORDER BY a.ParentId, a.Score DESC, a.CreationDate
), RecentSignificantEditsWindow AS (
    SELECT
      ph.PostId,
      ph.CreationDate,
      ph.UserId,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- title, body, tags edits
), RecentSignificantEdits AS (
    SELECT
        rse.PostId,
        rse.CreationDate,
        u.DisplayName AS EditorName,
        rse.PostHistoryTypeId
    FROM RecentSignificantEditsWindow rse
    LEFT JOIN Users u ON u.Id = rse.UserId
    WHERE rse.rn <= 3
), ClosedDuplicateQuestions AS (
    SELECT
        DISTINCT p.Id AS DuplicateId,
        pl.RelatedPostId AS OriginalQuestionId
    FROM PostLinks pl
    INNER JOIN Posts p ON p.Id = pl.PostId AND p.PostTypeId = 1
    WHERE LinkTypeId = 3 -- Duplicate
), UserActivityWins AS (
    SELECT 
      u.Id,
      u.DisplayName,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      b.GoldBadges,
      b.SilverBadges,
      b.BronzeBadges,
      COALESCE(uvs.UpVotesCast,0) AS VotesCastUp,
      COALESCE(uvs.DownVotesCast,0) AS VotesCastDown,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN RecursiveBadgeCount b ON b.UserId = u.Id
    LEFT JOIN UserVoteSummary uvs ON uvs.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, b.GoldBadges, b.SilverBadges, b.BronzeBadges, uvs.UpVotesCast, uvs.DownVotesCast
)
SELECT
    ua.Id AS UserId,
    ua.DisplayName,
    ua.ReputationRank,
    ua.ReputationRank * LOG(1 + UA.GoldBadges + 0.2) AS AdjustedReputationIndex,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,        
    ua.VotesCastUp,
    ua.VotesCastDown,
    tag_info.TopTags,
    closed_dupes_cnt.DuplicateClosedPosts,
    NULLIF(marked_dupes.DisplayFeatures, '') AS FeatureSummary,
    array_agg(DISTINCT 
        FORMAT('Answer(Id:%s Score:%s Date:%s)',xh.AnswerId, xh.Score, xh.CreationDate)
    ) FILTER (WHERE xh.AnswerId IS NOT NULL) AS TopAnswers,
    LEAD(ua.Id) OVER (ORDER BY ua.ReputationRank) AS NextUserByRepute,
    FIRST_VALUE(CONCAT(re_desc.PostId, '|', re_desc.EditorName)) OVER (PARTITION BY ua.Id ORDER BY re_desc.CreationDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS LatestEditInfo
FROM UserActivityWins ua
LEFT JOIN (
    SELECT
        te.UserId,
        string_agg(t.Tag, ',' ORDER BY count(*) DESC) AS TopTags
    FROM TagExploded te
    INNER JOIN Posts pt ON pt.Id = te.PostId
    INNER JOIN Users u ON u.Id = pt.OwnerUserId
    GROUP BY te.UserId
) as tag_info ON tag_info.UserId = ua.Id
LEFT JOIN (
    SELECT
        u.Id AS UserId,
        COUNT(distinct du.DuplicateId) AS DuplicateClosedPosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN ClosedDuplicateQuestions du ON du.DuplicateId = p.Id
    GROUP BY u.Id
) closed_dupes_cnt ON closed_dupes_cnt.UserId = ua.Id
LEFT JOIN (
    SELECT
        dl.UserId,
        STRING_AGG(CASE 
          WHEN b.Class = 1 THEN 'Gold' 
          WHEN b.Class = 2 THEN 'Silver' 
          WHEN b.Class = 3 THEN 'Bronze' 
          ELSE 'UnknownClass' END, ',') AS DisplayFeatures
    FROM Badges b
    JOIN Users dl ON dl.Id = b.UserId
    GROUP BY dl.UserId
    HAVING COUNT(b.Id) > 5
) marked_dupes ON marked_dupes.UserId = ua.Id
LEFT JOIN LATERAL (
     SELECT
        a.AnswerId,
        a.Score,
        a.CreationDate
     FROM TopAnswersPerQuestion a
     WHERE a.QuestionId IN (
        SELECT p.Id 
        FROM Posts p 
        WHERE p.OwnerUserId = ua.Id AND p.PostTypeId = 1
    )
    ORDER BY a.Score DESC LIMIT 3
) xh ON true
LEFT JOIN RecentSignificantEdits re_desc ON re_desc.PostId IN (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.Id
)
GROUP BY ua.Id, ua.DisplayName, ua.ReputationRank, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ua.VotesCastUp, ua.VotesCastDown, tag_info.TopTags, closed_dupes_cnt.DuplicateClosedPosts, marked_dupes.DisplayFeatures, re_desc.PostId, re_desc.EditorName, re_desc.CreationDate
ORDER BY ua.ReputationRank
FETCH FIRST 50 ROWS ONLY;