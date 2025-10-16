-- {"query": "1281.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1320} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, array[t.TagName] as Path, 1 as Level
    from Tags t
    where t.IsRequired = 1
    union all
    select child.Id, child.TagName, parent.Path || child.TagName, parent.Level + 1
    from Tags child
    join PostLinks pl on pl.PostId = child.ExcerptPostId
    join Posts p on p.Id = pl.RelatedPostId and p.PostTypeId = 1
    join RecursiveTagHierarchy parent on p.Tags like ('%<' || parent.TagName || '>%')
    where child.IsModeratorOnly = 0 and child.TagName <> all(parent.Path)
),
RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        coalesce(u.DisplayName, p.OwnerDisplayName) as OwnerName,
        coalesce(p.Title, '') as PostTitle,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate >= now() - interval '365 days' and p.Score > 0
),
PostsWithComments as (
    select 
        rp.*,
        c.CountComments,
        coalesce(nullif(substring(rp.Tags from '<([^>]+)>'), ''), 'NoTag') as FirstTag
    from RankedPosts rp
    left join (
        select PostId, count(*) as CountComments
        from Comments
        group by PostId
    ) c on c.PostId = rp.Id
),
PostVoteAggregates as (
    select v.PostId, 
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(distinct v.UserId) filter (where v.UserId is not null) as UniqueVoters,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    group by v.PostId
),
RecentPostEdits as (
    select ph.PostId, ph.UserId, ph.CreationDate,
        row_number() over(partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
),
LatestEdits as (
    select rpe.PostId, rpe.UserId, u.DisplayName as EditorName, rpe.CreationDate as EditDate from RecentPostEdits rpe
    left join Users u on u.Id = rpe.UserId
    where rpe.rn=1
),
ClosedQuestions as (
    select p.Id as QuestionId, cr.Name as CloseReason, ph.CreationDate as ClosedAt
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cr on cr.Id::varchar = ph.Comment
    where p.PostTypeId = 1
),
BenchmarkQuery AS (
    select 
        pwc.Id,
        pwc.PostTypeId,
        pwc.OwnerName,
        coalesce(pv.UpVotes,0) as UpVotes,
        coalesce(pv.DownVotes,0) as DownVotes,
        pwc.Score,
        pwc.ViewCount,
        pwc.AnswerCount,
        pwc.CountComments,
        pwc.FirstTag,
        le.EditorName,
        le.EditDate,
        cq.CloseReason,
        case 
            when pwc.Score > 100 and coalesce(pv.DownVotes,0) = 0 then 'Highly Approved'
            when pwc.Score < 0 then 'Negative Score'
            when cq.QuestionId is not null then 'Closed'
            else 'Normal'
        end as PostStatus,
        array_agg(distinct rth.Path order by rth.Level) filter (where rth.Id is not null) as TagHierarchies
    from PostsWithComments pwc
    left join PostVoteAggregates pv on pv.PostId = pwc.Id
    left join LatestEdits le on le.PostId = pwc.Id
    left join ClosedQuestions cq on cq.QuestionId = pwc.Id
    left join RecursiveTagHierarchy rth on rth.TagName = pwc.FirstTag
    where pwc.RankByScoreView <= 500
    group by pwc.Id, pwc.PostTypeId, pwc.OwnerName, pv.UpVotes, pv.DownVotes, pwc.Score, pwc.ViewCount, pwc.AnswerCount, pwc.CountComments, pwc.FirstTag, le.EditorName, le.EditDate, cq.CloseReason
    having 
        (pwc.ViewCount > 1000 or (coalesce(pv.UpVotes,0) - coalesce(pv.DownVotes,0)) > 10) 
        and (le.EditDate is null or le.EditDate > pwc.CreationDate)
)
select 
    bq.Id,
    pt.Name as PostTypeName,
    bq.OwnerName,
    bq.UpVotes,
    bq.DownVotes,
    bq.Score,
    bq.ViewCount,
    bq.AnswerCount,
    bq.CountComments,
    bq.FirstTag,
    bq.EditorName,
    bq.EditDate,
    bq.CloseReason,
    bq.PostStatus,
    coalesce(array_to_string(bq.TagHierarchies, ', '), '[]') as TagHierarchies,
    length(bq.OwnerName || coalesce(bq.EditorName, '')) as NameLengthSum,
    case when bq.EditDate is not null then date_part('epoch', now() - bq.EditDate)/86400 else null end as DaysSinceLastEdit
from BenchmarkQuery bq
join PostTypes pt on pt.Id = bq.PostTypeId
order by bq.UpVotes desc, bq.ViewCount desc, bq.Score desc
limit 100;