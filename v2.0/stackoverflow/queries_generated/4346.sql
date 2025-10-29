-- {"query": "4346.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1514} 

WITH
  UserPostInteraction AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(p.CreationDate) AS LastPostCreationDate
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      p.Id,
      p.OwnerUserId
  ),
  UserReputationChanges AS (
    SELECT
      UserId,
      COUNT(*) AS NumEdits,
      SUM(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
      SUM(CASE WHEN PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END) AS ModerationActionCount,
      MAX(CreationDate) AS LastEditDate
    FROM PostHistory
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  TopUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.Views AS TotalViews,
      u.UpVotes AS TotalUpVotesGiven,
      u.DownVotes AS TotalDownVotesGiven,
      COALESCE(COALESCE(uri.CommentCount, 0) + COALESCE(uri.UpVoteCount, 0) + COALESCE(uri.DownVoteCount, 0), 0) AS PostInteractionCount,
      COALESCE(uri.LastPostCreationDate, u.CreationDate) AS LastActivityDate,
      COALESCE(rc.NumEdits, 0) AS TotalEdits,
      COALESCE(rc.ContentEditCount, 0) AS ContentEdits,
      COALESCE(rc.ModerationActionCount, 0) AS ModerationActions,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1
        ELSE 0
      END AS HasWebsite,
      CASE
        WHEN u.AboutMe IS NOT NULL AND u.AboutMe != '' THEN 1
        ELSE 0
      END AS HasAboutMe,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 2
      ) AS SilverBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 3
      ) AS BronzeBadgeCount
    FROM Users AS u
    LEFT JOIN UserPostInteraction AS uri
      ON u.Id = uri.OwnerUserId
    LEFT JOIN UserReputationChanges AS rc
      ON u.Id = rc.UserId
    WHERE
      u.Reputation > 1000 AND u.Id > 0
  )
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.TotalViews,
  tu.TotalUpVotesGiven,
  tu.TotalDownVotesGiven,
  tu.PostInteractionCount,
  tu.LastActivityDate,
  tu.TotalEdits,
  tu.ContentEdits,
  tu.ModerationActions,
  tu.HasWebsite,
  tu.HasAboutMe,
  tu.GoldBadgeCount,
  tu.SilverBadgeCount,
  tu.BronzeBadgeCount,
  -- Calculate a composite performance score
  (
    tu.Reputation * 0.3
    + tu.PostInteractionCount * 0.2
    + tu.TotalEdits * 0.1
    + tu.ContentEdits * 0.15
    + tu.ModerationActions * 0.05
    + tu.GoldBadgeCount * 0.1
    + tu.SilverBadgeCount * 0.07
    + tu.BronzeBadgeCount * 0.03
    + tu.HasWebsite * 0.02
    + tu.HasAboutMe * 0.01
  ) AS PerformanceScore,
  -- Get the title of the most recently edited question by this user
  (
    SELECT
      p_inner.Title
    FROM Posts AS p_inner
    JOIN PostHistory AS ph_inner
      ON p_inner.Id = ph_inner.PostId
    WHERE
      p_inner.OwnerUserId = tu.UserId
      AND p_inner.PostTypeId = 1
      AND ph_inner.PostHistoryTypeId = 4 -- Edit Title
      AND ph_inner.UserId = tu.UserId
    ORDER BY
      ph_inner.CreationDate DESC
    LIMIT 1
  ) AS MostRecentEditedQuestionTitle,
  -- Check if the user has ever received a 'gold' badge for a specific tag (example: 'sql')
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b_tag
      WHERE
        b_tag.UserId = tu.UserId
        AND b_tag.Name = 'Awesome-SQL' -- Example gold badge name
        AND b_tag.Class = 1
    ) THEN 'Yes'
    ELSE 'No'
  END AS HasAwesomeSQLBadge,
  -- Calculate the average score of questions this user has accepted answers for
  (
    SELECT
      AVG(p_accepted.Score)
    FROM Posts AS p_accepted
    WHERE
      p_accepted.AcceptedAnswerId IS NOT NULL
      AND p_accepted.OwnerUserId = tu.UserId
  ) AS AvgScoreOfAcceptedAnswers,
  -- Find the count of posts with titles containing 'performance' and owned by this user
  (
    SELECT
      COUNT(*)
    FROM Posts AS p_perf
    WHERE
      p_perf.OwnerUserId = tu.UserId
      AND p_perf.Title ILIKE '%performance%'
  ) AS PerformanceRelatedQuestionsCount
FROM TopUsers AS tu
ORDER BY
  PerformanceScore DESC
LIMIT 100;
