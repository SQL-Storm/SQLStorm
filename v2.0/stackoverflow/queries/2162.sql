-- {"query": "2162.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1265}
with recursive RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        u.Reputation,
        row_number() over (partition by t.Id order by u.Reputation desc nulls last) as UserRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where coalesce(t.IsModeratorOnly, false) = false
), 

UserBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),

PostAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        count(c.Id) over (partition by p.Id) as CommentsCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank,
        dense_rank() over (order by p.ViewCount desc nulls last) as ViewRank,
        p.ClosedDate as ClosedDate
    from Posts p
    left join Comments c on c.PostId = p.Id
),

AcceptedAnswerScores as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    where q.PostTypeId = 1
),

CloseReasonsCount as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, cr.Name
),

RecursiveCloseReasonHierarchy as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        0 as Depth,
        ph.CreationDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10

    union all

    select
        r.PostId,
        ph.Comment,
        r.Depth + 1,
        ph.CreationDate
    from RecursiveCloseReasonHierarchy r
    join PostHistory ph on ph.PostId = r.PostId and ph.PostHistoryTypeId = 11 and ph.CreationDate > (
        select max(ph2.CreationDate) from PostHistory ph2 where ph2.PostId = r.PostId and ph2.PostHistoryTypeId = 10
    )
    where r.Depth < 5
)

select
    tas.TagName,
    tas.Count as TagQuestionCount,
    tas.AnswerCount as TagAnswerCount,
    tas.Reputation as TopUserReputation,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pa.Id as PostId,
    pa.PostTypeId,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    acs.AnswerScore as AcceptedAnswerScore,
    crc.CloseReason,
    crc.CloseVotesCount,
    case when pa.IsClosed = 1 then 'Closed' else 'Open' end as PostStatus,
    case
        when pa.Score > 100 then 'Hot question with score: ' || cast(pa.Score as varchar)
        when pa.ViewCount > 10000 then 'Very popular post'
        else 'Regular activity'
    end as PostPopularity,
    concat_ws(' | ',
        coalesce(pa.Tags, 'No Tags'),
        coalesce(cast(pa.OwnerUserId as varchar), 'Anonymous'),
        coalesce(u.DisplayName, 'Unknown')
    ) as PostSummary,
    cnts.TotalComments,
    cnts.MaxCommentScore,
    cnts.AvgCommentLength,
    (select count(distinct v.Id)
     from Votes v
     where v.PostId = pa.Id and v.VoteTypeId = 2) as UpvotesCount,
    (select count(distinct v.Id)
     from Votes v
     where v.PostId = pa.Id and v.VoteTypeId = 3) as DownvotesCount
from RecursiveTagCounts tas
left join UserBadgeStats ubs on ubs.UserId = (
    select p2.OwnerUserId from Posts p2 where p2.Id = tas.TagId fetch first 1 row only
)
left join PostAggregates pa on pa.OwnerUserId = ubs.UserId
left join AcceptedAnswerScores acs on acs.QuestionId = pa.Id
left join CloseReasonsCount crc on crc.PostId = pa.Id
left join (
    select 
        c.PostId, 
        count(*) as TotalComments,
        max(c.Score) as MaxCommentScore,
        avg(char_length(c.Text)) as AvgCommentLength
    from Comments c
    group by c.PostId
) cnts on cnts.PostId = pa.Id
left join Users u on u.Id = pa.OwnerUserId
where tas.UserRank = 1
and (pa.Score > 10 or pa.ViewCount > 5000 or pa.FavoriteCount > 3)
and (
    pa.ClosedDate is null 
    or (pa.ClosedDate is not null and pa.CreationDate > (date '2024-10-01' - interval '1 year'))
)
order by pa.ScoreRank, pa.ViewRank desc, tas.Count desc
limit 100;