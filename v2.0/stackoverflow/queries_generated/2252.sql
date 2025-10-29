-- {"query": "2252.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1396} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.TagName] as Path
    from Tags t
    where not exists (
        select 1 from Posts p
        join Posts p2 on p.Id = p2.ParentId
        where p.Tags like '%' || t.TagName || '%'
    )
    union all
    select 
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Path || t2.TagName
    from RecursiveTagHierarchy r
    join Posts p on p.Tags like '%' || r.TagName || '%'
    join Tags t2 on p.Tags like '%' || t2.TagName || '%'
    where not t2.TagName = any(r.Path)
),
UserReputRank as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        row_number() over (order by u.Reputation desc nulls last) as RepRank,
        rank() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc nulls last) as LocationRepRank
    from Users u
    where u.Reputation is not null
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as TotalAnswers,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesOnQuestion,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesOnQuestion,
        count(distinct c.Id) as TotalCommentsOnQuestion
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = q.Id
    left join Comments c on c.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
PostHistoryAnalysis as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        p.Title,
        ph.UserId,
        u.DisplayName,
        ph.CreationDate,
        ph.Comment,
        count(*) over (partition by ph.PostId, ph.PostHistoryTypeId) as HistoryTypeCountPerPost
    from PostHistory ph
    left join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId in (10,11,12,13,19,20)
),
UserBadgeAgg as (
    select 
        b.UserId,
        u.DisplayName,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeEarned,
        count(distinct b.Name) as UniqueBadges
    from Badges b
    join Users u on u.Id = b.UserId
    group by b.UserId, u.DisplayName
),
DuplicatePosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        ph.Comment as CloseReason,
        ph.CreationDate as CloseDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    left join PostHistory ph on ph.PostId = pl.PostId and ph.PostHistoryTypeId = 10 and ph.Comment = '101' -- Duplicate close reason
    where pl.LinkTypeId = 3
)
select 
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.QuestionCreation,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.TotalAnswers,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    qas.UpVotesOnQuestion,
    qas.DownVotesOnQuestion,
    qas.TotalCommentsOnQuestion,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.UniqueBadges,
    uba.LastBadgeEarned,
    ur.Reputation,
    ur.RepRank,
    ur.LocationRepRank,
    phs.HistoryTypeCountPerPost,
    phs.PostHistoryTypeId,
    phs.UserId as EditorUserId,
    phs.DisplayName as EditorDisplayName,
    dup.DuplicateTitle,
    dup.CloseReason,
    dup.CloseDate,
    case
        when qas.QuestionScore > 100 then 'High Score'
        when qas.QuestionScore between 50 and 100 then 'Medium Score'
        else 'Low Score'
    end as ScoreCategory,
    case 
        when uba.GoldBadges > 5 then 'Elite'
        when uba.GoldBadges between 1 and 5 then 'Experienced'
        else 'Novice'
    end as UserBadgeLevel,
    concat(
        left(qas.Title, 30),
        '...',
        coalesce(substr(uba.DisplayName, 1, 10), 'Anonymous'),
        '-',
        to_char(qas.QuestionCreation, 'YYYY-MM-DD')
    ) as TitleSnippet
from QuestionAnswerStats qas
left join UserBadgeAgg uba on uba.UserId = (
    select OwnerUserId from Posts p where p.Id = qas.QuestionId and OwnerUserId is not null limit 1
)
left join UserReputRank ur on ur.Id = (
    select OwnerUserId from Posts p where p.Id = qas.QuestionId and OwnerUserId is not null limit 1
)
left join PostHistoryAnalysis phs on phs.PostId = qas.QuestionId
left join DuplicatePosts dup on dup.PostId = qas.QuestionId
where (qas.TotalAnswers > 5 or qas.QuestionScore > 10)
  and (uba.GoldBadges > 0 or ur.Reputation > 2000)
order by qas.QuestionScore desc, uba.GoldBadges desc, ur.Reputation desc
limit 100;