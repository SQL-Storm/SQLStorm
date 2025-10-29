WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.Score AS QuestionScore,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 day')
  ),
  TopAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      RANK() OVER (
        PARTITION BY
          p.ParentId
        ORDER BY
          p.Score DESC,
          p.CreationDate ASC
      ) AS rank_num
    FROM Posts p
    WHERE
      p.PostTypeId = 2
  ),
  QuestionAnswerStats AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.OwnerUserId AS QuestionOwnerUserId,
      rq.QuestionCreationDate,
      rq.AnswerCount,
      rq.QuestionScore,
      MAX(ta.AnswerScore) AS MaxAnswerScore,
      AVG(ta.AnswerScore) AS AvgAnswerScore,
      SUM(CASE WHEN ta.AnswerScore > 0 THEN 1 ELSE 0 END) AS PositiveAnswerCount,
      COUNT(ta.AnswerId) AS TotalAnswerCount
    FROM RecentQuestions rq
    LEFT JOIN TopAnswers ta
      ON rq.QuestionId = ta.QuestionId
    WHERE
      rq.rn <= 100
    GROUP BY
      rq.QuestionId,
      rq.Title,
      rq.OwnerUserId,
      rq.QuestionCreationDate,
      rq.AnswerCount,
      rq.QuestionScore
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
      (
        SELECT
          COUNT(*)
        FROM Badges b
        WHERE
          b.UserId = u.Id
          AND b.Class = 1
      ) AS GoldBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM Badges b
        WHERE
          b.UserId = u.Id
          AND b.Class = 2
      ) AS SilverBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM Badges b
        WHERE
          b.UserId = u.Id
          AND b.Class = 3
      ) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostVoteSummary AS (
    SELECT
      p.Id AS PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCount
    FROM Posts p
    JOIN Votes v
      ON p.Id = v.PostId
    GROUP BY
      p.Id
  )
SELECT
  qas.QuestionId,
  qas.Title AS QuestionTitle,
  ua_q.DisplayName AS QuestionOwnerDisplayName,
  ua_q.Reputation AS QuestionOwnerReputation,
  ua_q.GoldBadgeCount AS QuestionOwnerGoldBadges,
  qas.QuestionCreationDate,
  qas.QuestionScore,
  qas.AnswerCount,
  qas.MaxAnswerScore,
  qas.AvgAnswerScore,
  qas.PositiveAnswerCount,
  pvs.TotalUpVotes AS QuestionTotalUpVotes,
  pvs.TotalDownVotes AS QuestionTotalDownVotes,
  pvs.FavoriteCount AS QuestionFavoriteCount,
  COUNT(DISTINCT ph.Id) AS PostHistoryEntryCount,
  COALESCE(MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN ph.Comment ELSE NULL END), 'No Edit Comment') AS LatestEditComment,
  SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenEvents,
  AVG(
    CASE
      WHEN ua_a.UserId IS NOT NULL THEN ua_a.Reputation
      ELSE 0
    END
  ) AS AvgAnswererReputation,
  STRING_AGG(DISTINCT tag.TagName, ', ') AS Tags,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.PostId = qas.QuestionId
      AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount
FROM QuestionAnswerStats qas
JOIN UserActivity ua_q
  ON qas.QuestionOwnerUserId = ua_q.UserId
LEFT JOIN PostVoteSummary pvs
  ON qas.QuestionId = pvs.PostId
LEFT JOIN PostHistory ph
  ON qas.QuestionId = ph.PostId
  AND ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,24,35,36,50,52,53,66)
LEFT JOIN Posts p_tags
  ON qas.QuestionId = p_tags.Id
LEFT JOIN LATERAL (
  SELECT regexp_split_to_table(regexp_replace(regexp_replace(p_tags.Tags, '<', '', 'g'), '>', '', 'g'), '><' ) AS TagName
) tag_name ON TRUE
LEFT JOIN Tags tag
  ON tag.TagName = tag_name.TagName
LEFT JOIN TopAnswers ta_for_avg_user
  ON qas.QuestionId = ta_for_avg_user.QuestionId
LEFT JOIN UserActivity ua_a
  ON ta_for_avg_user.OwnerUserId = ua_a.UserId
GROUP BY
  qas.QuestionId,
  qas.Title,
  ua_q.DisplayName,
  ua_q.Reputation,
  ua_q.GoldBadgeCount,
  qas.QuestionCreationDate,
  qas.QuestionScore,
  qas.AnswerCount,
  qas.MaxAnswerScore,
  qas.AvgAnswerScore,
  qas.PositiveAnswerCount,
  pvs.TotalUpVotes,
  pvs.TotalDownVotes,
  pvs.FavoriteCount
HAVING
  qas.QuestionScore > 10
  AND qas.AvgAnswerScore IS NOT NULL
ORDER BY
  qas.QuestionScore DESC,
  qas.QuestionCreationDate DESC
LIMIT 50;