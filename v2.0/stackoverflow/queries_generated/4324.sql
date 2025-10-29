-- {"query": "4324.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1572} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.CreationDate,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.PostTypeId
        ORDER BY
          p.Score DESC,
          p.CreationDate DESC
      ) AS rn_score_desc,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.PostTypeId
        ORDER BY
          p.AnswerCount DESC,
          p.CreationDate DESC
      ) AS rn_answer_count_desc,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.PostTypeId
        ORDER BY
          p.FavoriteCount DESC,
          p.CreationDate DESC
      ) AS rn_favorite_count_desc,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.PostTypeId
        ORDER BY
          p.ViewCount DESC,
          p.CreationDate DESC
      ) AS rn_view_count_desc,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountTotal,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVoteCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS PostStatus
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
      LEFT JOIN Votes AS v
        ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
      AND p.Score >= 0
      AND p.CreationDate > '2023-01-01'
  ),
  UserPostSummary AS (
    SELECT
      rp.OwnerUserId,
      COUNT(rp.PostId) AS TotalPosts,
      AVG(CAST(rp.Score AS DECIMAL(10, 2))) AS AvgScore,
      AVG(CAST(rp.CommentCountTotal AS DECIMAL(10, 2))) AS AvgTotalComments,
      SUM(rp.UpVoteCount) AS TotalUpVotesReceived,
      SUM(rp.DownVoteCount) AS TotalDownVotesReceived,
      COUNT(DISTINCT CASE WHEN rp.PostTypeName = 'Question' THEN rp.PostId ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN rp.PostTypeName = 'Answer' THEN rp.PostId ELSE NULL END) AS AnswerCount,
      COUNT(DISTINCT CASE WHEN rp.PostStatus = 'Closed' THEN rp.PostId ELSE NULL END) AS ClosedPostCount,
      COUNT(DISTINCT CASE WHEN rp.PostStatus = 'Community Owned' THEN rp.PostId ELSE NULL END) AS CommunityOwnedPostCount,
      MAX(rp.CreationDate) AS LastPostCreationDate
    FROM
      RankedPosts AS rp
    WHERE
      rp.PostTypeId IN (1, 2)
    GROUP BY
      rp.OwnerUserId
  )
SELECT
  u.DisplayName AS UserName,
  ups.TotalPosts,
  ups.AvgScore,
  ups.AvgTotalComments,
  ups.TotalUpVotesReceived,
  ups.TotalDownVotesReceived,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.ClosedPostCount,
  ups.CommunityOwnedPostCount,
  ups.LastPostCreationDate,
  rp_q.PostId AS TopQuestionId,
  rp_q.Score AS TopQuestionScore,
  rp_a.PostId AS TopAnswerId,
  rp_a.Score AS TopAnswerScore,
  rp_f.PostId AS TopFavoritePostId,
  rp_f.FavoriteCount AS TopFavoriteCount,
  COALESCE(b.Name, 'No Badge') AS LatestBadgeName,
  b.Date AS LatestBadgeDate,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteType,
  LENGTH(u.AboutMe) AS AboutMeLength,
  CASE
    WHEN u.DownVotes > u.UpVotes * 5 THEN 'High Negative Ratio'
    WHEN u.UpVotes > u.DownVotes * 10 THEN 'High Positive Ratio'
    ELSE 'Balanced Ratio'
  END AS VoteRatioCategory,
  CASE
    WHEN u.Views > 1000000 THEN 'Very High Views'
    WHEN u.Views > 100000 THEN 'High Views'
    ELSE 'Standard Views'
  END AS ViewCategory,
  COALESCE(
    (
      SELECT
        COUNT(pl.Id)
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = rp_q.PostId AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinksToTopQuestion
FROM
  Users AS u
LEFT JOIN
  UserPostSummary AS ups
  ON u.Id = ups.OwnerUserId
LEFT JOIN
  RankedPosts AS rp_q
  ON u.Id = rp_q.OwnerUserId AND rp_q.PostTypeId = 1 AND rp_q.rn_score_desc = 1
LEFT JOIN
  RankedPosts AS rp_a
  ON u.Id = rp_a.OwnerUserId AND rp_a.PostTypeId = 2 AND rp_a.rn_answer_count_desc = 1
LEFT JOIN
  RankedPosts AS rp_f
  ON u.Id = rp_f.OwnerUserId AND rp_f.PostTypeId = 1 AND rp_f.rn_favorite_count_desc = 1
LEFT JOIN (
  SELECT
    b_inner.*,
    ROW_NUMBER() OVER (PARTITION BY b_inner.UserId ORDER BY b_inner.Date DESC) AS rn_badge
  FROM
    Badges AS b_inner
  WHERE
    b_inner.Class IN (1, 2)
) AS b
  ON u.Id = b.UserId AND b.rn_badge = 1
WHERE
  ups.TotalPosts > 10
ORDER BY
  ups.AvgScore DESC,
  ups.TotalPosts DESC
LIMIT 100;
