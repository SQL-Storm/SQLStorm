-- {"query": "1450.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1402} 
with recursive RecursiveTags as (
    select t.Id, t.TagName, array[t.Id] as TagPath
    from Tags t
    union all
    select t2.Id, t2.TagName, rt.TagPath || t2.Id
    from Tags t2
    join RecursiveTags rt on t2.Id <> all(rt.TagPath) and substring(t2.TagName, 1, length(rt.TagName)) = rt.TagName
),
UserBadgeRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by u.Id order by b.Class) as RankWithinUser
    from Users u
    left join Badges b on b.UserId = u.Id and b.Date > u.CreationDate
    where u.DisplayName is not null
    group by u.Id, u.DisplayName, b.Class
),
TopContributors as (
    select UserId, DisplayName, sum(BadgeCount) as TotalBadges,
        max(case when Class=1 then BadgeCount else 0 end) as GoldBadges,
        max(case when Class=2 then BadgeCount else 0 end) as SilverBadges,
        max(case when Class=3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadgeRanks 
    group by UserId, DisplayName
    having sum(BadgeCount) > 10
),
PostActivityStats as (
    select 
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.Title, p.Tags,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6,19)) over (partition by p.Id) as SignificantEditCount,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate >= p.CreationDate) as CommentsAfterCreate,
        (select sum(VoteTypeId=2::int) from Votes v where v.PostId = p.Id) as UpVotesReceived,
        (select sum(VoteTypeId=3::int) from Votes v where v.PostId = p.Id) as DownVotesReceived,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostScore
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.OwnerUserId is not null
),
PostsWithLinkedDuplicates as (
    select p.Id, p.Title, count(pl.Id) filter (where lt.Name='Duplicate') as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by p.Id, p.Title
),
CloseReasonCount as (
    select ph.Comment as CloseReasonId, crt.Name, count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
AnswerQuality as (
    select a.ParentId as QuestionId, count(*) as AnswerCount, avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore, count(case when a.Score < 0 then 1 end) as CountNegativeScoreAnswers,
        count(case when a.Score >= 10 then 1 end) as CountHighScoreAnswers,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
UserEngagement as (
    select u.Id, u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId=2) as AnswerCount,
        coalesce(max(p.CreationDate),u.CreationDate) as LastPostDate,
        count(distinct ph.Id) as EditCount,
        sum(case when exists(
            select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 8
        ) then 1 else 0 end) as BountiedPostsCount,
        cast(coalesce((julianday(u.LastAccessDate) - julianday(u.CreationDate)),0) as int) as DaysActive
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
)
select distinct
    tg.TagName as RootTag,
    cu.DisplayName as TopContributor,
    pas.Title as RecentPostTitle,
    pas.Score as RecentPostScore,
    pc.DuplicateCount,
    arc.AnswerCount,
    arc.AvgAnswerScore,
    arc.CountNegativeScoreAnswers,
    frac.QuestionCount,
    frac.AnswerCount,
    absorbed.close_reason_name,
    close_re.CloseCount,
    ue.LastPostDate,
    ue.EditCount,
    ue.BountiedPostsCount,
    ue.DaysActive,
    rank() over (partition by tg.Id order by arc.AvgAnswerScore DESC nulls last) as TagTopQuestionsRanking
from RecursiveTags tg
join PostsWithLinkedDuplicates pc on pc.Id = (
    select p2.Id from Posts p2
    where p2.PostTypeId=1 and p2.Tags like '%'||tg.TagName||'%'
    order by p2.CreationDate desc limit 1)
left join AnswerQuality arc on arc.QuestionId = pc.Id
left join TopContributors cu on cu.UserId = (
    select OwnerUserId from Posts p3 
    where p3.PostTypeId = 1 and p3.Tags like '%'||tg.TagName||'%'
    group by OwnerUserId order by count(*) desc limit 1)
left join PostActivityStats pas on pas.Id = pc.Id
left join CloseReasonCount close_re on close_re.CloseReasonId = (
    select comment from PostHistory ph where ph.PostId=pc.Id and ph.PostHistoryTypeId=10 order by ph.CreationDate desc limit 1)
left join UserEngagement ue on ue.Id = cu.UserId
order by tg.TagName, arc.AvgAnswerScore desc nulls last
limit 100;