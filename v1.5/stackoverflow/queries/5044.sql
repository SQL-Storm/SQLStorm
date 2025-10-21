with RecentActiveUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from
        Users u
    where
        u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
),
TopTags as (
    select
        t.TagName,
        sum(t.Count) as TotalCount
    from
        Tags t
    group by
        t.TagName
    having
        sum(t.Count) > 1000
    order by
        TotalCount desc
    limit 10
),
PopularQuestions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Body,
        p.Tags,
        sum(vote.Score) as TotalCommentScore,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as QuestionRank
    from
        Posts p
        left join Comments vote on vote.PostId = p.Id
    where
        p.PostTypeId = 1
        and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    group by
        p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.Title, p.Body, p.Tags
),
DupQuestions as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate as LinkCreationDate,
        lt.Name as LinkType
    from
        PostLinks pl
        join LinkTypes lt on pl.LinkTypeId = lt.Id
    where
        pl.LinkTypeId = 3
),
AnswersAgg as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        max(p.Score) as MaxAnswerScore,
        avg(p.Score) filter (where p.Score > 0) as AvgPosAnswerScore
    from
        Posts p
    where
        p.PostTypeId = 2
    group by
        p.ParentId
)
select
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    tp.TagName,
    pq.QuestionId,
    pq.Title,
    pq.Score as QuestionScore,
    pq.TotalCommentScore,
    array_to_string(regexp_matches(pq.Tags, '<(' || tp.TagName || ')>'), ',') as TagMatched,
    aa.AnswerCount,
    aa.MaxAnswerScore,
    aa.AvgPosAnswerScore,
    coalesce(dq.LinkType, 'None') as DuplicateStatus,
    b.BadgeCount,
    case
        when pq.Score is null then 'No Score'
        when pq.Score >= 10 then 'Hot'
        when pq.Score between 5 and 9 then 'Warm'
        when pq.Score between 1 and 4 then 'Tepid'
        else 'Cold'
    end as Popularity,
    pq.CreationDate as QuestionCreated,
    ru.LastAccessDate as UserLastSeen,
    (extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - pq.CreationDate))/3600) * 1.0 as QuestionAgeHours,
    (ru.Reputation / greatest(aa.AnswerCount,1))::numeric(10,2) as ReputationPerAnswer
from
    RecentActiveUsers ru
    cross join TopTags tp
    left join PopularQuestions pq
        on pq.OwnerUserId = ru.UserId
        and pq.Tags like '%<' || tp.TagName || '>%'
    left join DupQuestions dq
        on dq.PostId = pq.QuestionId
    left join AnswersAgg aa
        on aa.QuestionId = pq.QuestionId
    left join (
        select
            b.UserId,
            count(*) as BadgeCount
        from
            Badges b
        where
            b.Date > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
        group by
            b.UserId
    ) b on b.UserId = ru.UserId
where
    (pq.Score is null or pq.Score >= 2)
    and (ru.Reputation > 500 or aa.MaxAnswerScore > 3 or b.BadgeCount >= 1)
    and (tp.TagName is not null)
    and (
        pq.Body is null or
        (lower(pq.Body) like '%performance%' or lower(pq.Body) like '%benchmark%' or length(trim(pq.Body)) > 100)
    )
group by
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    tp.TagName,
    pq.QuestionId,
    pq.Title,
    pq.Score,
    pq.TotalCommentScore,
    pq.Body,
    pq.Tags,
    aa.AnswerCount,
    aa.MaxAnswerScore,
    aa.AvgPosAnswerScore,
    dq.LinkType,
    b.BadgeCount,
    ru.LastAccessDate,
    pq.CreationDate
order by
    Popularity desc,
    ReputationPerAnswer desc nulls last,
    ru.Reputation desc,
    pq.Score desc nulls last
limit 100;