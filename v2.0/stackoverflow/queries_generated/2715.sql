-- {"query": "2715.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1534} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
PostScores as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        coalesce(vtUp.UpVotes, 0) as TotalUpVotes,
        coalesce(vtDown.DownVotes, 0) as TotalDownVotes,
        (coalesce(vtUp.UpVotes, 0) - coalesce(vtDown.DownVotes, 0)) as NetVotes,
        case when p.Tags is not null then array_length(regexp_split_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) else 0 end as TagCount,
        p.FavoriteCount,
        p.CommentCount,
        p.Score
    from Posts p
    left join (
        select PostId, count(*) as UpVotes
        from Votes 
        where VoteTypeId = 2
        group by PostId
    ) vtUp on vtUp.PostId = p.Id
    left join (
        select PostId, count(*) as DownVotes
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vtDown on vtDown.PostId = p.Id
),
TopTags as (
    select 
        tg.TagName,
        count(*) as TagUsageCount,
        max(p.Score) as MaxPostScore,
        avg(p.Score) as AvgPostScore
    from Tags tg
    left join Posts p on p.Tags LIKE '%' || concat('<', tg.TagName, '>') || '%'
    group by tg.TagName
    having count(*) > 100
),
UserBadgeSummary as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
ClosedQuestionReasons as (
    select 
        p.Id as QuestionId,
        cht.Name as CloseReason,
        ph.CreationDate as ClosedAt,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    join CloseReasonTypes cht on cht.Id = cast(ph.Comment as integer)
    left join Users u on u.Id = ph.UserId
    where p.PostTypeId = 1 -- questions only
),
AnswerRanks as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
UserPostSummary as (
    select 
        u.Id as UserId, 
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        coalesce(max(a.Score),0) as MaxAnswerScore,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(avg(p.Score),0) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId as OriginalPostId,
        pl.RelatedPostId as DuplicatePostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate
),
RecentCommentsContributions as (
    select
        c.UserId,
        u.DisplayName,
        count(*) as RecentCommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct substring(c.Text from 1 for 20), ', ') as SampleCommentTexts
    from Comments c
    join Users u on u.Id = c.UserId
    where c.CreationDate > now() - interval '30 days'
    group by c.UserId, u.DisplayName
)
select
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.CreationDate as UserCreated,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalAnswerScore,
    up.MaxAnswerScore,
    up.TotalPostScore,
    up.AvgPostScore,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(ubs.TotalBadges,0) as TotalBadges,
    coalesce(ubs.LastBadgeDate, to_timestamp(0)) as LastBadgeDate,
    coalesce(rcc.RecentCommentCount,0) as RecentComments,
    rcc.LastCommentDate,
    rcc.SampleCommentTexts,
    case when dq.DuplicatePostId is not null then dq.DuplicateTitle else null end as LatestDuplicateOfTitle,
    case when dq.DuplicatePostId is not null then dq.CreationDate else null end as LatestDuplicateLinkDate
from RecursiveUserActivity rua
join UserPostSummary up on up.UserId = rua.UserId
left join UserBadgeSummary ubs on ubs.UserId = rua.UserId
left join RecentCommentsContributions rcc on rcc.UserId = rua.UserId
left join LATERAL (
    select dq2.*
    from DuplicateLinks dq2
    join Posts p on p.Id = dq2.OriginalPostId
    where p.OwnerUserId = rua.UserId
    order by dq2.CreationDate desc
    limit 1
) dq on true
where rua.PostRank = 1
order by up.TotalPostScore desc, rua.Reputation desc
limit 50;