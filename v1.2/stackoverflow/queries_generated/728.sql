-- {"query": "728.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1667} 
with RecursivePostHierarchy as (
    select
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        1 as Level,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.Title,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Tags,
        c.OwnerUserId,
        r.Level + 1,
        r.Path || c.Id
    from Posts c
    join RecursivePostHierarchy r on c.ParentId = r.Id
    where c.PostTypeId = 2 -- answers or further posts linked to question
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostVoteAggregates as (
    select
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    group by v.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(a.ViewCount) as SumAnswerViews
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
UserActivityWindows as (
    select
        u.Id,
        count(p.Id) over (partition by u.Id order by p.CreationDate rows between 6 preceding and current row) as PostsLast7,
        count(c.Id) over (partition by u.Id order by c.CreationDate rows between 6 preceding and current row) as CommentsLast7
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
),
TaggedQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc
)
select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate,
    coalesce(pva.UpVotes,0) as QuestionUpVotes,
    coalesce(pva.DownVotes,0) as QuestionDownVotes,
    qa.TotalAnswers,
    coalesce(qa.AvgAnswerScore,0) as AverageAnswerScore,
    coalesce(qa.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(qa.SumAnswerViews,0) as SumAnswerViews,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    u.DisplayName as OwnerName,
    case
        when u.Location is null then 'Unknown'
        when length(u.Location) > 50 then substring(u.Location from 1 for 50) || '...'
        else u.Location
    end as UserLocation,
    array_agg(distinct tq.TagName) filter (where tq.TagName is not null) as TagsList,
    string_agg(distinct coalesce(dq.RelatedPostId::text, 'None'), ', ') as DuplicateQuestionIds,
    lph.PostHistoryTypeId as LatestHistoryType,
    lph.Comment as LatestHistoryComment,
    row_number() over (partition by u.Id order by q.CreationDate desc) as UserRecentQuestionRank,
    case
        when q.ClosedDate is not null then 'Closed'
        when q.AcceptedAnswerId is not null then 'Answered'
        else 'Open'
    end as QuestionStatus,
    w.PostsLast7,
    w.CommentsLast7,
    -- Complex calculation: weighted popularity score
    (coalesce(pva.UpVotes,0) * 2 + coalesce(qa.AvgAnswerScore,0) * 1.5 + coalesce(qa.TotalAnswers,0) * 1.2 +
     coalesce(ub.GoldBadges,0) * 5 + coalesce(ub.SilverBadges,0) * 3 + coalesce(ub.BronzeBadges,0) * 1) /
    nullif(extract(day from now() - q.CreationDate),0) as PopularityScore,
    -- String expression with NULL logic and concatenation
    coalesce(u.DisplayName, 'Anonymous') || ' (' || coalesce(u.EmailHash, 'no-email') || ')' as UserIdentity,
    -- Subquery: Count of comments on question
    (select count(*) from Comments c2 where c2.PostId = q.Id) as CommentCount,
    -- Correlated subquery: Latest answer score
    (select max(a2.Score) from Posts a2 where a2.ParentId = q.Id and a2.PostTypeId = 2) as LatestAnswerMaxScore
from Posts q
left join PostVoteAggregates pva on pva.PostId = q.Id
left join QuestionAnswerStats qa on qa.QuestionId = q.Id
left join Users u on u.Id = q.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = u.Id
left join TaggedQuestions tq on tq.Id = q.Id
left join DuplicateLinks dq on dq.PostId = q.Id
left join LatestPostHistories lph on lph.PostId = q.Id
left join UserActivityWindows w on w.Id = u.Id
where q.PostTypeId = 1
and q.Score > 5
and (
    -- complicated predicate with NULL logic and string pattern matching
    (q.Tags like '%<sql>%'
     or exists (
         select 1 from Posts a where a.ParentId = q.Id and a.Body ilike '%performance%'
     )
    )
)
group by q.Id, q.Title, q.CreationDate, pva.UpVotes, pva.DownVotes, qa.TotalAnswers, qa.AvgAnswerScore, qa.MaxAnswerScore, qa.SumAnswerViews,
         ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, u.Reputation, u.CreationDate, u.DisplayName, u.Location, dq.RelatedPostId,
         lph.PostHistoryTypeId, lph.Comment, q.ClosedDate, q.AcceptedAnswerId, w.PostsLast7, w.CommentsLast7, u.EmailHash
order by PopularityScore desc
limit 100;