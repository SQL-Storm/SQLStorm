WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionsAsked,
        (SELECT AVG(CAST(Score AS NUMERIC)) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AvgAnswerScore
    FROM Users u
), RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        ph.CreationDate AS LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS MovingAvgScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (4,5,6) 
        AND ph.CreationDate = (
            SELECT MAX(ph2.CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = p.Id
        )
    WHERE p.PostTypeId IN (1,2)
)
SELECT 
    rp.PostId,
    rp.Title,
    CASE 
        WHEN rp.Tags IS NULL THEN NULL
        WHEN POSITION('>' IN rp.Tags) > 0 AND POSITION('<' IN rp.Tags) > 0 
        THEN SUBSTRING(rp.Tags FROM POSITION('<' IN rp.Tags) + 1 FOR POSITION('>' IN rp.Tags) - POSITION('<' IN rp.Tags) - 1)
        ELSE rp.Tags
    END AS PrimaryTag,
    rp.Score,
    rp.MovingAvgScore,
    us.Reputation,
    us.GoldBadges,
    COALESCE(u.DisplayName, 'Community Wiki') AS Author,
    (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpvoteCount,
    (SELECT STRING_AGG(lt.Name, ', ') FROM PostLinks pl JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId WHERE pl.PostId = rp.PostId) AS LinkTypes,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId = 10) 
        THEN (
            SELECT crt.Name 
            FROM PostHistory ph2 
            JOIN CloseReasonTypes crt ON CAST(ph2.Comment AS INTEGER) = crt.Id 
            WHERE ph2.PostId = rp.PostId AND ph2.PostHistoryTypeId = 10
            FETCH FIRST 1 ROWS ONLY
        )
        ELSE 'Open'
    END AS CloseStatus,
    RANK() OVER (ORDER BY us.Reputation DESC) AS GlobalRank,
    DENSE_RANK() OVER (PARTITION BY (CASE WHEN us.GoldBadges > 0 THEN 1 ELSE 0 END) ORDER BY us.Reputation DESC) AS GoldUserRank
FROM RankedPosts rp
LEFT JOIN UserStats us ON us.UserId = rp.OwnerUserId
LEFT JOIN Users u ON u.Id = rp.OwnerUserId
WHERE rp.UserPostRank <= 5
    AND rp.Score > COALESCE(rp.PrevScore, 0)
    AND (us.AvgAnswerScore > 10 OR us.QuestionsAsked > 20)
    AND (rp.Tags LIKE '%<sql>%' OR rp.Tags IS NULL)
GROUP BY
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.MovingAvgScore,
    us.Reputation,
    us.GoldBadges,
    u.DisplayName,
    rp.PrevScore,
    rp.UserPostRank,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastEditDate,
    us.UpVotes,
    us.DownVotes,
    us.UserId
ORDER BY rp.MovingAvgScore DESC, us.Reputation DESC
FETCH FIRST 100 ROWS ONLY;