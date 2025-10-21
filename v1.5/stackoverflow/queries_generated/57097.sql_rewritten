-- {"query": "57097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1058} 
WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
		  LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    ORDER BY
        TotalScore DESC
    LIMIT 10
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        t.TagName, t.Count
    ORDER BY
        TotalViews DESC
    LIMIT 10
),
RecentActivity AS (
		SELECT
				p.Id AS PostId,
				p.PostTypeId,
				p.CreationDate,
				p.Score,
				p.ViewCount,
				p.OwnerUserId,
				u.DisplayName AS OwnerDisplayName,
				p.LastActivityDate,
				p.Title,
				c.Count AS CommentCount,
				v.Count AS VoteCount
		FROM
				Posts p
		JOIN (
				SELECT
						PostId,
						COUNT(*) AS Count
				FROM
						Comments
				GROUP BY
						PostId
		) c ON p.Id = c.PostId
		JOIN (
				SELECT
						PostId,
						COUNT(*) AS Count
				FROM
						Votes
				GROUP BY
						PostId
		) v ON p.Id = v.PostId
		LEFT JOIN
				Users u ON p.OwnerUserId = u.Id
		WHERE
				p.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days'
		ORDER BY
				p.LastActivityDate DESC
		LIMIT 50
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.TotalViews,
    tu.CommentCount,
    tu.VoteCount,
    tu.LastActivity,
    tt.TagName,
    tt.Count AS TagCount,
    tt.AvgPostScore,
    tt.TotalViews AS TagTotalViews,
    tt.PostCount AS TagPostCount,
    tt.VoteCount AS TagVoteCount,
    ra.PostId,
    ra.PostTypeId,
    ra.CreationDate,
    ra.Score AS RecentPostScore,
    ra.ViewCount AS RecentPostViews,
    ra.OwnerUserId AS RecentPostOwnerUserId,
    ra.OwnerDisplayName,
    ra.LastActivityDate AS RecentPostActivity,
    ra.Title AS RecentPostTitle,
    ra.CommentCount AS RecentPostCommentCount,
    ra.VoteCount AS RecentPostVoteCount
FROM
    TopUsers tu
CROSS JOIN
    TopTags tt
JOIN
    RecentActivity ra ON ra.OwnerUserId = tu.UserId;