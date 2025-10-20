SELECT
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViews,
    CASE 
      WHEN p.Tags IS NULL OR length(p.Tags) < 2 THEN 0
      ELSE array_length(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '<>'), 1)
    END AS TagCount,
    u.Id AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(cmt.CommentCount, 0) AS CommentCount,
    COALESCE(phs.TotalEdits, 0) AS TotalEdits,
    COALESCE(phs.TotalRevisions, 0) AS TotalRevisions,
    votes.VoteSummary,
    badges.BadgeNames AS BadgeSummary
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    (
      SELECT
        p2.ParentId,
        COUNT(*) AS AnswerCount
      FROM
        Posts p2
      WHERE
        p2.PostTypeId = 2
      GROUP BY
        p2.ParentId
    ) a ON p.Id = a.ParentId
LEFT JOIN
    (
      SELECT
        c.PostId,
        COUNT(*) AS CommentCount
      FROM
        Comments c
      GROUP BY
        c.PostId
    ) cmt ON p.Id = cmt.PostId
LEFT JOIN
    (
      SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66) THEN 1 END) AS TotalEdits,
        COUNT(*) AS TotalRevisions
      FROM
        PostHistory ph
      GROUP BY
        ph.PostId
    ) phs ON p.Id = phs.PostId
LEFT JOIN
    (
      SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
        CASE
          WHEN SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) = 0 THEN 'No Votes'
          ELSE 'Up: ' || SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) || ', Down: ' || SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
        END AS VoteSummary
      FROM
        Votes v
      GROUP BY
        v.PostId
    ) votes ON p.Id = votes.PostId
LEFT JOIN
    (
      SELECT
        b.UserId,
        COUNT(*) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
      FROM
        Badges b
      GROUP BY
        b.UserId
    ) badges ON u.Id = badges.UserId
WHERE
    p.PostTypeId = 1
    AND p.CreationDate > DATE '2020-01-01'
ORDER BY
    p.CreationDate DESC
LIMIT 100;