-- {"query": "54016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 5185} 
WITH PostSummary AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.Reputation,
        u.DisplayName,
        COALESCE(b.TagCount,0) AS BadgeCount
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS TagCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
),
TagList AS (
    SELECT
        ps.Id,
        ps.Title,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM ps.Tags), '><')) AS Tag
    FROM PostSummary ps
),
VoteStats AS (
    SELECT
        pv.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS Accepted
    FROM Votes pv
    JOIN VoteTypes vt ON vt.Id = pv.VoteTypeId
    GROUP BY pv.PostId
)
SELECT
    tl.Tag,
    COUNT(*) AS PostCount,
    SUM(ps.Score) AS TotalScore,
    SUM(ps.ViewCount) AS TotalViews,
    AVG(vs.UpVotes) AS AvgUpVotes,
    MAX(ps.Reputation) AS MaxOwnerRep,
    MIN(ps.Reputation) AS MinOwnerRep,
    COUNT(DISTINCT ps.Id) FILTER (WHERE ps.Score > 0) AS PositiveScorePosts
FROM TagList tl
JOIN PostSummary ps ON ps.Id = tl.Id
JOIN VoteStats vs ON vs.PostId = ps.Id
GROUP BY tl.Tag
ORDER BY PostCount DESC, AvgUpVotes DESC
LIMIT 200;