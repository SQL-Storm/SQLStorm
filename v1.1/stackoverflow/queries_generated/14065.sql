-- {"query": "14065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 154110, "output_tokens": 66465} 
WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostType,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Open'
    END AS PostStatus,
    CASE
      WHEN ph.PostHistoryTypeId = 10 THEN CONCAT('Closed: ', cr.Name)
      WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
      WHEN ph.PostHistoryTypeId = 12 THEN 'Deleted'
      WHEN ph.PostHistoryTypeId = 13 THEN 'Undeleted'
      WHEN ph.PostHistoryTypeId = 14 THEN 'Locked'
      WHEN ph.PostHistoryTypeId = 15 THEN 'Unlocked'
      WHEN ph.PostHistoryTypeId = 16 THEN 'Community Owned'
      ELSE NULL
    END AS PostHistoryEvent,
    CASE
      WHEN v.VoteTypeId = 2 THEN 1
      WHEN v.VoteTypeId = 3 THEN -1
      ELSE 0
    END AS VoteType,
    CASE
      WHEN v.VoteTypeId = 8 THEN v.BountyAmount
      ELSE 0
    END AS BountyAmount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS INT) = cr.Id
  LEFT JOIN Votes v ON p.Id = v.PostId
  WHERE p.PostTypeId IN (1, 2)
)
SELECT
  PostId,
  SUM(Score) AS TotalScore,
  SUM(ViewCount) AS TotalViews,
  SUM(AnswerCount) AS TotalAnswers,
  SUM(CommentCount) AS TotalComments,
  SUM(FavoriteCount) AS TotalFavorites,
  COUNT(DISTINCT OwnerUserId) AS UniqueOwnerCount,
  AVG(Reputation) AS AvgReputation,
  SUM(UpVotes) AS TotalUpVotes,
  SUM(DownVotes) AS TotalDownVotes,
  COUNT(DISTINCT BadgeName) AS UniqueBadgeCount,
  COUNT(CASE WHEN BadgeClass = 1 THEN 1 END) AS GoldBadgeCount,
  COUNT(CASE WHEN BadgeClass = 2 THEN 1 END) AS SilverBadgeCount,
  COUNT(CASE WHEN BadgeClass = 3 THEN 1 END) AS BronzeBadgeCount,
  COUNT(CASE WHEN BadgeTagBased = 1 THEN 1 END) AS TagBasedBadgeCount,
  COUNT(CASE WHEN PostType = 'Question' THEN 1 END) AS QuestionCount,
  COUNT(CASE WHEN PostType = 'Answer' THEN 1 END) AS AnswerCount,
  COUNT(CASE WHEN PostStatus = 'Closed' THEN 1 END) AS ClosedPostCount,
  COUNT(CASE WHEN PostStatus = 'Community Owned' THEN 1 END) AS CommunityOwnedPostCount,
  COUNT(CASE WHEN PostHistoryEvent IS NOT NULL THEN 1 END) AS PostHistoryEventCount,
  SUM(CASE WHEN VoteType = 1 THEN 1 ELSE 0 END) AS TotalUpVotes,
  SUM(CASE WHEN VoteType = -1 THEN 1 ELSE 0 END) AS TotalDownVotes,
  SUM(BountyAmount) AS TotalBountyAmount
FROM cte
GROUP BY PostId
ORDER BY TotalScore DESC
LIMIT 10;