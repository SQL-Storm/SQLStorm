-- {"query": "4012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1456} 
with Recursive_TagCounts as (
    select
        t.Id,
        t.TagName,
        array_agg(distinct p.Id) filter (where p.Id is not null) as PostIds,
        t.Count as TagCount
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    group by t.Id, t.TagName, t.Count

    union all

    select
        rt.Id,
        rt.TagName,
        rt.PostIds,
        rt.TagCount
    from Recursive_TagCounts rt
),
UserActivityRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        rank() over (
            order by count(distinct p.Id) filter (where p.PostTypeId = 2) desc
        ) as AnswerRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoresWithWindows as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextScore,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
FilteredPostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p.Score as RelatedPostScore,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
    where pl.LinkTypeId in (1,3)
),
PostCloseReasonsAggregated as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseReasonCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
      and crt.Id is not null
    group by ph.PostId, crt.Name
),
UserVoteSummary as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount,
        sum(v.BountyAmount) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId, vt.Name
),
UserCommentsAggregate as (
    select
        c.UserId,
        count(*) filter (where c.Text ilike '%sql%') as SqlCommentsCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
QuestionsWithAnswerStats as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.MaxAnswerScore, 0) as HighestAnswerScore,
        u.DisplayName as QuestionOwner,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        pcr.CloseReasonName,
        pcr.CloseReasonCount
    from Posts q
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join PostCloseReasonsAggregated pcr on pcr.PostId = q.Id
    where q.PostTypeId = 1
)
select
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeCount,
    us.VoteTypeName,
    us.VoteCount,
    us.TotalBounty,
    coalesce(uc.SqlCommentsCount, 0) as SqlCommentsCount,
    uc.LastCommentDate,
    q.Id as SampleQuestionId,
    q.Title as SampleQuestionTitle,
    q.AnswerCount as SampleQuestionAnswerCount,
    q.HighestAnswerScore as SampleQuestionMaxAnswerScore,
    q.HasAcceptedAnswer,
    q.CloseReasonName,
    q.CloseReasonCount,
    array_agg(distinct ft.TagName) filter (where ft.TagCount > 100) as PopularTags,
    pl.LinkTypeName,
    pl.RelatedPostId,
    pl.RelatedPostScore,
    ps.PrevScore,
    ps.NextScore,
    ps.ScoreRank
from UserActivityRanks ua
left join UserVoteSummary us on us.UserId = ua.UserId
left join UserCommentsAggregate uc on uc.UserId = ua.UserId
left join lateral (
    select qtmp.*
    from QuestionsWithAnswerStats qtmp
    where qtmp.OwnerUserId = ua.UserId
    order by qtmp.QuestionScore desc nulls last
    limit 1
) q on true
left join Recursive_TagCounts ft on ft.Id = (
    select t.Id from Tags t order by t.Count desc limit 1
)
left join FilteredPostLinks pl on pl.PostId = q.Id
left join PostScoresWithWindows ps on ps.PostId = q.Id
where ua.AnswerRank <= 100
group by ua.UserId, ua.DisplayName, ua.QuestionCount, ua.AnswerCount, ua.BadgeCount, us.VoteTypeName, us.VoteCount, us.TotalBounty, uc.SqlCommentsCount, uc.LastCommentDate, q.Id, q.Title, q.AnswerCount, q.HighestAnswerScore, q.HasAcceptedAnswer, q.CloseReasonName, q.CloseReasonCount, pl.LinkTypeName, pl.RelatedPostId, pl.RelatedPostScore, ps.PrevScore, ps.NextScore, ps.ScoreRank
order by ua.AnswerCount desc, ua.BadgeCount desc
limit 50;