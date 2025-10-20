with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (partition by t.IsModeratorOnly order by t.Count desc) as RankByModStatus,
        t.IsModeratorOnly
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
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
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
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct case when v.VoteTypeId = 2 then v.Id end) as UpVotesGiven,
        count(distinct case when v.VoteTypeId = 3 then v.Id end) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    rtc.TagName,
    rtc.Count as TagCount,
    rtc.TotalAnswers,
    rtc.TotalViews,
    rtc.RankByModStatus,
    ubs.DisplayName as BadgeUser,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pas.Id as PostId,
    pas.PostTypeId,
    pas.Score,
    pas.ViewCount,
    pas.CommentCount,
    pas.UpVotes,
    pas.DownVotes,
    pas.RecentPostRank,
    coalesce(pas.PrevScore, 0) as PreviousPostScore,
    coalesce(pas.NextScore, 0) as NextPostScore,
    cqwr.CloseDate,
    cqwr.CloseReason,
    cqwr.ClosedByUserName,
    dl.OriginalTitle as DuplicateOriginalTitle,
    dl.DuplicateTitle as DuplicateOfTitle,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.LastPostDate,
    uas.LastCommentDate
from RecursiveTagCounts rtc
left join UserBadgeStats ubs on ubs.UserId = (
    select p.OwnerUserId
    from Posts p
    where p.Tags like '%' || '<' || rtc.TagName || '>' || '%'
    limit 1
)
left join PostActivityWindow pas on pas.Tags like '%' || '<' || rtc.TagName || '>' || '%' and pas.RecentPostRank = 1
left join ClosedQuestionsWithReasons cqwr on cqwr.PostId = pas.Id
left join DuplicateLinks dl on dl.PostId = pas.Id
left join UserActivitySummary uas on uas.UserId = pas.OwnerUserId
where rtc.RankByModStatus <= 10
order by rtc.IsModeratorOnly desc, rtc.Count desc, pas.Score desc
limit 100;