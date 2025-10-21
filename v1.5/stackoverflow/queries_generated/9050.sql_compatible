WITH
LatestPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE p.PostTypeId IN (1, 2)
),
UserLatest AS (
    SELECT
        OwnerUserId AS UserId,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS RecentQ,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentA
    FROM LatestPosts
    WHERE rn <= 3
    GROUP BY OwnerUserId
),
TagUsage AS (
    SELECT
        p.Id AS PostId,
        UNNEST(
          STRING_TO_ARRAY(
            SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2),
            '><'
          )
        ) AS TagName
    FROM Posts AS p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT
        TagName,
        COUNT(*) AS QCount
    FROM TagUsage
    GROUP BY TagName
    HAVING COUNT(*) > 100
    ORDER BY QCount DESC
    LIMIT 5
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges AS b
    GROUP BY b.UserId
),
VoteSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes AS v
    JOIN Posts AS p ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
DupQuestions AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) AS DupCount
    FROM Posts AS p
    JOIN PostLinks AS pl
      ON pl.PostId = p.Id
     AND pl.LinkTypeId = 3
    GROUP BY p.OwnerUserId
),
Combined AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ul.RecentQ, 0) AS RecentQ,
        COALESCE(ul.RecentA, 0) AS RecentA,
        COALESCE(ub.TotalBadges, 0) AS TotalBadges,
        COALESCE(ub.Gold, 0) AS Gold,
        COALESCE(ub.Silver, 0) AS Silver,
        COALESCE(ub.Bronze, 0) AS Bronze,
        COALESCE(vs.UpVotes, 0) AS ReceivedUpVotes,
        COALESCE(vs.DownVotes, 0) AS ReceivedDownVotes,
        COALESCE(dq.DupCount, 0) AS DupCount,
        RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        CASE
          WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown'
          ELSE SUBSTRING(u.Location FOR 15)
        END AS ShortLocation,
        (SELECT MAX(c.Score) FROM Comments AS c WHERE c.UserId = u.Id) AS MaxCommentScore,
        (
          SELECT COUNT(*)
          FROM TagUsage AS tu
          WHERE tu.PostId IN (
              SELECT p2.Id FROM Posts AS p2 WHERE p2.OwnerUserId = u.Id
          )
            AND tu.TagName IN (SELECT TagName FROM TopTags)
        ) AS TopTagPosts
    FROM Users AS u
    LEFT JOIN UserLatest AS ul ON u.Id = ul.UserId
    LEFT JOIN UserBadges AS ub ON u.Id = ub.UserId
    LEFT JOIN VoteSummary AS vs ON u.Id = vs.UserId
    LEFT JOIN DupQuestions AS dq ON u.Id = dq.UserId
    WHERE u.Reputation > COALESCE((SELECT AVG(Reputation) FROM Users), 0)
)
SELECT *
FROM Combined
UNION ALL
SELECT
    NULL AS Id,
    'ALL USERS' AS DisplayName,
    NULL AS Reputation,
    SUM(RecentQ) AS RecentQ,
    SUM(RecentA) AS RecentA,
    SUM(TotalBadges) AS TotalBadges,
    SUM(Gold) AS Gold,
    SUM(Silver) AS Silver,
    SUM(Bronze) AS Bronze,
    SUM(ReceivedUpVotes) AS ReceivedUpVotes,
    SUM(ReceivedDownVotes) AS ReceivedDownVotes,
    SUM(DupCount) AS DupCount,
    NULL AS RepRank,
    NULL AS ShortLocation,
    SUM(MaxCommentScore) AS MaxCommentScore,
    SUM(TopTagPosts) AS TopTagPosts
FROM Combined
ORDER BY RepRank NULLS LAST
LIMIT 50;