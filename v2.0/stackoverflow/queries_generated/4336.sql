-- {"query": "4336.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1763} 

WITH
  RankedUserVotes AS (
    SELECT
      v.UserId,
      v.PostId,
      v.VoteTypeId,
      v.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) as vote_rank
    FROM Votes AS v
    WHERE
      v.VoteTypeId IN (2, 3) /* UpMod or DownMod */
  ),
  UserVoteSummary AS (
    SELECT
      UserId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 ELSE NULL END) AS total_upvotes,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 ELSE NULL END) AS total_downvotes,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE -1 END) AS net_vote_score
    FROM RankedUserVotes
    GROUP BY
      UserId
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      COALESCE(p.ViewCount, 0) AS PostViewCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed,
      CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS is_community_owned,
      COUNT(DISTINCT c.Id) AS comment_count,
      COUNT(DISTINCT v_up.Id) AS upvote_count,
      COUNT(DISTINCT v_down.Id) AS downvote_count,
      COUNT(DISTINCT ph.Id) AS history_entry_count,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END) AS moderation_action_count,
      STRING_AGG(DISTINCT t.TagName, ', ') AS tags_list
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v_up
      ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2
    LEFT JOIN Votes AS v_down
      ON p.Id = v_down.PostId AND v_down.VoteTypeId = 3
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId
    LEFT JOIN (
      SELECT
        Id,
        TagName
      FROM Tags
    ) AS t
      ON FIND_IN_SET(t.TagName, REPLACE(REPLACE(p.Tags, '<', ''), '>', ',')) > 0
    WHERE
      p.PostTypeId IN (1, 2) /* Questions and Answers */
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      p.CommunityOwnedDate
  ),
  UserPostContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT pq.Id) AS question_count,
      COUNT(DISTINCT pa.Id) AS answer_count,
      SUM(CASE WHEN pa.Id IS NOT NULL THEN pa.Score ELSE 0 END) AS total_answer_score,
      AVG(CASE WHEN pq.Id IS NOT NULL THEN pq.CommentCount ELSE NULL END) AS avg_question_comments,
      MAX(CASE WHEN pq.Id IS NOT NULL THEN pq.FavoriteCount ELSE 0 END) AS max_question_favorites,
      COUNT(DISTINCT b.Id) AS badge_count,
      MAX(b.Date) AS last_badge_date
    FROM Users AS u
    LEFT JOIN Posts AS pq
      ON u.Id = pq.OwnerUserId AND pq.PostTypeId = 1 /* Questions */
    LEFT JOIN Posts AS pa
      ON u.Id = pa.OwnerUserId AND pa.PostTypeId = 2 /* Answers */
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  upc.UserId,
  upc.DisplayName,
  upc.Reputation,
  upc.UserCreationDate,
  upc.UserViews,
  upc.UserUpVotes,
  upc.UserDownVotes,
  upc.question_count,
  upc.answer_count,
  upc.total_answer_score,
  upc.avg_question_comments,
  upc.max_question_favorites,
  upc.badge_count,
  upc.last_badge_date,
  COALESCE(ruv.total_upvotes, 0) AS recent_upvotes,
  COALESCE(ruv.total_downvotes, 0) AS recent_downvotes,
  COALESCE(ruv.net_vote_score, 0) AS recent_net_vote_score,
  COUNT(DISTINCT pe.PostId) AS total_posts_engaged_with,
  SUM(CASE WHEN pe.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_engaged_with,
  SUM(CASE WHEN pe.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers_engaged_with,
  AVG(pe.PostScore) AS avg_post_score_engaged_with,
  SUM(pe.upvote_count) AS total_post_upvotes_engaged_with,
  SUM(pe.downvote_count) AS total_post_downvotes_engaged_with,
  SUM(pe.comment_count) AS total_post_comments_engaged_with,
  SUM(pe.history_entry_count) AS total_post_history_entries,
  SUM(pe.moderation_action_count) AS total_post_moderation_actions,
  COUNT(DISTINCT pl.PostId) AS linked_posts_count,
  COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId ELSE NULL END) AS duplicate_links_count,
  GROUP_CONCAT(DISTINCT pe.tags_list) AS aggregated_tags_list
FROM UserPostContribution AS upc
LEFT JOIN UserVoteSummary AS ruv
  ON upc.UserId = ruv.UserId
LEFT JOIN PostEngagement AS pe
  ON upc.UserId = pe.OwnerUserId
LEFT JOIN PostLinks AS pl
  ON upc.UserId = pl.PostId
GROUP BY
  upc.UserId,
  upc.DisplayName,
  upc.Reputation,
  upc.UserCreationDate,
  upc.UserViews,
  upc.UserUpVotes,
  upc.UserDownVotes,
  recent_upvotes,
  recent_downvotes,
  recent_net_vote_score
ORDER BY
  upc.Reputation DESC,
  upc.UserCreationDate ASC
LIMIT 100;
