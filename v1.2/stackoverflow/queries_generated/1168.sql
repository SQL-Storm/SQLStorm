-- {"query": "1168.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1738} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        case when p.OwnerUserId is not null then 1 else 0 end as PostCount
    from
        Tags t
    left join
        Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    union all
    select
        rtc.TagId,
        rtc.TagName,
        rtc.ViewCount + coalesce(p.ViewCount,0),
        rtc.Score + coalesce(p.Score,0),
        rtc.PostCount + case when p.OwnerUserId is not null then 1 else 0 end
    from
        RecursiveTagCounts rtc
    join
        Posts p on p.PostTypeId = 1 and p.Tags like '%' || rtc.TagName || '%'
    where
        rtc.PostCount < 100 -- limit recursion artificially to avoid infinite
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn
    from
        Badges b
    -- only top ranks per user
    where
        b.TagBased = 0
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        count(a.Id) filter (where a.Score > 0) as PositiveAnswerCount,
        sum(coalesce(a.Score,0)) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        coalesce(q.FavoriteCount,0) as FavoriteCount,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from
        Posts q
    left join
        Posts a on a.ParentId = q.Id and a.PostTypeId=2
    where
        q.PostTypeId = 1
    group by
        q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.FavoriteCount, q.ClosedDate
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from
        Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by
        u.Id, u.DisplayName, u.Reputation
),
HighImpactQuestions as (
    select
        qas.QuestionId,
        ua.DisplayName as OwnerName,
        qas.QuestionScore,
        qas.TotalAnswerScore,
        qas.PositiveAnswerCount,
        qas.FavoriteCount,
        qas.IsClosed,
        rtc.TagName,
        max(pbwn.Class) as MaxBadgeClassOwner
    from QuestionAnswerStats qas
    join UserActivity ua on ua.UserId = qas.OwnerUserId
    left join RecursiveTagCounts rtc on rtc.TagName = any(string_to_array(substring((select Tags from Posts where Id = qas.QuestionId), 2, length((select Tags from Posts where Id = qas.QuestionId))-2), '><'))
    left join UserBadgeRanks pbwn on pbwn.UserId = ua.UserId and pbwn.rn = 1
    where qas.QuestionScore > 5 and qas.PositiveAnswerCount > 2
    group by 
        qas.QuestionId, ua.DisplayName, qas.QuestionScore, qas.TotalAnswerScore, qas.PositiveAnswerCount, qas.FavoriteCount, qas.IsClosed, rtc.TagName
),
ClosedQuestionsWithDetails as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from
        PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where
        ph.PostHistoryTypeId = 10 -- Post Closed
),
DuplicationLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from 
        PostLinks pl
    join 
        LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where
        pl.LinkTypeId = 3 -- Duplicates
)
select distinct
    hiq.QuestionId,
    hiq.OwnerName,
    hiq.QuestionScore,
    hiq.TotalAnswerScore,
    hiq.PositiveAnswerCount,
    hiq.FavoriteCount,
    case when hiq.IsClosed = 1 then 'Closed' else 'Open' end as Status,
    coalesce(hiq.TagName, '(none)') as TagName,
    coalesce(crd.CloseReasonName, 'N/A') as CloseReason,
    coalesce(dl.RelatedPostId, -1) as DuplicateOfId,
    coalesce(dl.RelatedPostTitle, '') as DuplicateOfTitle,
    hiq.MaxBadgeClassOwner,
    ua.ReputationRank,
    -- Create a calculated Renaissance Score based on multiple factors
    (hiq.QuestionScore * 2 + hiq.TotalAnswerScore * 3 + hiq.FavoriteCount * 5 + (100 - ua.ReputationRank) * 0.1) /
        nullif(1 + greatest(hiq.PositiveAnswerCount, 1), 0) as RenaissanceScore,
    -- Window function to rank questions by RenaissanceScore within the same tag
    rank() over (partition by coalesce(hiq.TagName, 'none') order by
        (hiq.QuestionScore * 2 + hiq.TotalAnswerScore * 3 + hiq.FavoriteCount * 5 + (100 - ua.ReputationRank) * 0.1) /
        nullif(1 + greatest(hiq.PositiveAnswerCount, 1), 0) desc) as TagRenaissanceRank,
    -- Complex string concatenations and null logic for display name and about me snippet
    left(coalesce(ua.DisplayName, concat('User_', hiq.OwnerName)), 40) || ' - ' ||
    coalesce(nullif(substring(ua.DisplayName from '^.{0,3}$'), ''), '---') as UserAlias,
    case when ua.Reputation >= 10000 then 'Expert' when ua.Reputation >= 1000 then 'Experienced' else 'Beginner' end as UserLevel,
    -- Extract year from question creation date via subquery and show years active
    (select extract(year from max(CreationDate)) from Posts p where p.OwnerUserId = ua.UserId) - 
    (select extract(year from min(CreationDate)) from Posts p where p.OwnerUserId = ua.UserId) as YearsActive
from
    HighImpactQuestions hiq
join
    UserActivity ua on ua.UserId = (select OwnerUserId from Posts where Id = hiq.QuestionId)
left join
    ClosedQuestionsWithDetails crd on crd.PostId = hiq.QuestionId
left join
    DuplicationLinks dl on dl.PostId = hiq.QuestionId
where
    RenaissanceScore > 50
order by
    RenaissanceScore desc,
    hiq.QuestionScore desc,
    hiq.PositiveAnswerCount desc
limit 100;