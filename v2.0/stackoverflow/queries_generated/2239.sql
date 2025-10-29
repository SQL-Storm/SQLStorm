-- {"query": "2239.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1374} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, b.Class

    union all

    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        case when r.Class is null then 3 else r.Class - 1 end,
        r.BadgeCount
    from RecursiveUserBadgeCounts r
    where r.Class > 1
),
TopUsers as (
    select distinct on (UserId) UserId, DisplayName, Reputation, Class, BadgeCount
    from RecursiveUserBadgeCounts
    order by UserId, Class
),
PostRanks as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        row_number() over (partition by p.PostTypeId order by p.CreationDate asc) as CreationOrderAsc,
        row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as CreationOrderDesc
    from Posts p
    where p.PostTypeId in (1,2) and p.OwnerUserId is not null
),
FilteredPosts as (
    select
        pr.*,
        u.DisplayName,
        u.Reputation,
        tb.Class as BadgeClass,
        tb.BadgeCount
    from PostRanks pr
    join Users u on pr.OwnerUserId = u.Id
    left join TopUsers tb on u.Id = tb.UserId and tb.Class = 1
    where pr.ScoreRank <= 100
),
CommentsOnTopPosts as (
    select
        c.Id as CommentId,
        c.PostId,
        c.UserId as CommentUserId,
        u.DisplayName as CommentUserName,
        c.Score as CommentScore,
        c.CreationDate as CommentDate,
        count(*) over (partition by c.PostId) as CommentCountPerPost,
        rank() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as CommentRank
    from Comments c
    left join Users u on c.UserId = u.Id
    where c.PostId in (select Id from FilteredPosts)
),
LinksSummary as (
    select
        l.PostId,
        l.LinkTypeId,
        count(*) as LinkCount
    from PostLinks l
    group by l.PostId, l.LinkTypeId
),
PostHistoryAggregates as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        count(*) as PhCount,
        max(ph.CreationDate) as LastEdit
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId, ph.PostHistoryTypeId
),
QuestionAnswers as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
)
select
    fp.Id as PostId,
    fp.PostTypeId,
    fp.Title,
    substr(fp.Title || ' - ' || coalesce(fp.DisplayName, 'Anonymous'), 1, 100) as TitleSnippet,
    fp.Score,
    fp.ViewCount,
    fp.Reputation as OwnerReputation,
    coalesce(fp.BadgeCount, 0) as GoldBadges,
    psa.QAnswerCounts,
    pha.LastEdit,
    coalesce(lsLinked.LinkCount,0) as LinkedCount,
    coalesce(lsDuplicate.LinkCount,0) as DuplicateCount,
    ca.AnswerCount,
    ca.TopAnswerId,
    ca.TopAnswerScore,
    ctp.CommentCountPerPost,
    ctp.TopCommentUser,
    ctp.TopCommentScore
from FilteredPosts fp
left join (
    select
        q.Id,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        max(a.Id) filter (where row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) = 1) as TopAnswerId,
        max(a.Score) filter (where row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) = 1) as TopAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
) ca on fp.Id = ca.Id
left join (
    select
        ph.PostId,
        max(ph.LastEdit) as LastEdit
    from PostHistoryAggregates ph
    group by ph.PostId
) pha on fp.Id = pha.PostId
left join (
    select
        l.PostId,
        sum(case when l.LinkTypeId = 1 then l.LinkCount else 0 end) as LinkedCount,
        sum(case when l.LinkTypeId = 3 then l.LinkCount else 0 end) as DuplicateCount
    from LinksSummary l
    group by l.PostId
) lsLinked on fp.Id = lsLinked.PostId
left join (
    select
        c.PostId,
        max(c.CommentCountPerPost) as CommentCountPerPost,
        max(c.CommentUserName) filter (where c.CommentRank = 1) as TopCommentUser,
        max(c.CommentScore) filter (where c.CommentRank = 1) as TopCommentScore
    from (
        select 
            c.PostId,
            c.CommentId,
            c.CommentUserName,
            c.CommentScore,
            c.CommentRank,
            c.CommentCountPerPost
        from CommentsOnTopPosts c
    ) c
    group by c.PostId
) ctp on fp.Id = ctp.PostId
order by fp.Score desc, fp.ViewCount desc, fp.CreationDate desc
limit 50;