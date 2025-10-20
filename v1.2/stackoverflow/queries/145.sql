with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.IsModeratorOnly order by t.Count desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsRequired = false
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.AcceptedAnswerId
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        u.DisplayName as OwnerName,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join Posts rp on rp.Id = pl.RelatedPostId
    left join Users u on u.Id = p.OwnerUserId
    where pl.LinkTypeId = 3
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as TotalUpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        case when max(p.CreationDate) is not null and min(p.CreationDate) is not null then
            extract(epoch from max(p.CreationDate) - min(p.CreationDate))/86400
        else null end as ActiveDays
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    u.DisplayName as User,
    u.QuestionCount,
    u.AnswerCount,
    u.CommentCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.ActiveDays,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubs.TagBasedBadges, 0) as TagBasedBadges,
    max(paw.Score) as HighestPostScore,
    min(paw.Score) as LowestPostScore,
    avg(paw.Score) as AvgPostScore,
    count(distinct dq.PostId) as DuplicatePostsCount,
    string_agg(distinct dt.TagName, ', ') as TopTags,
    string_agg(distinct cqr.CloseReason, ', ') as CloseReasons
from UserActivitySummary u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join PostActivityWindow paw on paw.OwnerUserId = u.Id
left join DuplicateLinks dq on dq.OwnerName = u.DisplayName
left join RecursiveTagCounts dt on dt.rn <= 3 and dt.TagName is not null
left join ClosedQuestionsWithReasons cqr on cqr.ClosedByUserId = u.Id
where u.QuestionCount > 5
group by u.DisplayName, u.QuestionCount, u.AnswerCount, u.CommentCount, u.TotalUpVotes, u.TotalDownVotes, u.ActiveDays, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBasedBadges
having avg(paw.Score) > 0
order by AvgPostScore desc, u.QuestionCount desc
limit 50;