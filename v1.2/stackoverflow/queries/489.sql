with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like ('%' || '<' || t.TagName || '>' || '%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate > (cast('2024-10-01' as date) - interval '365 days')
),
TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > (cast('2024-10-01' as date) - interval '365 days')
    group by b.UserId, b.Class
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ubg.GoldCount, 0) as GoldBadges,
        coalesce(ubg.SilverCount, 0) as SilverBadges,
        coalesce(ubg.BronzeCount, 0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) as GoldCount,
            sum(case when Class = 2 then BadgeCount else 0 end) as SilverCount,
            sum(case when Class = 3 then BadgeCount else 0 end) as BronzeCount
        from UserBadgeRanks
        group by UserId
    ) ubg on ubg.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, ubg.GoldCount, ubg.SilverCount, ubg.BronzeCount
),
RecentClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) and ph.PostHistoryTypeId = 10
    join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = p.OwnerUserId
    where ph.CreationDate > (cast('2024-10-01' as date) - interval '180 days')
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswersWithComments as (
    select
        ar.AnswerId,
        ar.QuestionId,
        ar.Score as AnswerScore,
        ar.CreationDate as AnswerCreationDate,
        c.Id as CommentId,
        c.Text as CommentText,
        c.Score as CommentScore,
        c.CreationDate as CommentCreationDate,
        u.DisplayName as CommentUser
    from AnswerRanks ar
    left join Comments c on c.PostId = ar.AnswerId
    left join Users u on u.Id = c.UserId
    where ar.AnswerRank <= 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpVotes,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownVotes,
        max(p.Score) filter (where p.OwnerUserId = u.Id) as MaxPostScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    t.TagName,
    t.PostId,
    t.Score as PostScore,
    t.ViewCount as PostViews,
    t.CreationDate as PostCreation,
    coalesce(u.DisplayName, 'Community') as PostOwner,
    u.Reputation as OwnerReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgPostScore,
    ua.MaxPostScore,
    ua.TotalQuestionViews,
    rc.ClosedDate,
    rc.CloseReason,
    rc.Title as ClosedQuestionTitle,
    rc.OwnerName as ClosedQuestionOwner,
    rc.Score as ClosedQuestionScore,
    rc.ViewCount as ClosedQuestionViews,
    ta.AnswerId,
    ta.AnswerScore,
    ta.AnswerCreationDate,
    ta.CommentId,
    ta.CommentText,
    ta.CommentScore,
    ta.CommentCreationDate,
    ta.CommentUser,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    uas.MaxPostScore as UserMaxPostScore,
    uas.FirstPostDate,
    uas.LastPostDate
from TopTagPosts t
left join Users u on u.Id = t.OwnerUserId
left join UserAggregates ua on ua.Id = t.OwnerUserId
left join RecentClosedQuestions rc on rc.PostId = t.PostId
left join TopAnswersWithComments ta on ta.QuestionId = t.PostId
left join UserActivitySummary uas on uas.UserId = t.OwnerUserId
where
    (coalesce(ua.GoldBadges,0) + coalesce(ua.SilverBadges,0) + coalesce(ua.BronzeBadges,0)) > 0
    and (t.Score > 5 or t.ViewCount > 1000)
    and (rc.ClosedDate is null or rc.ClosedDate > (cast('2024-10-01' as date) - interval '90 days'))
order by t.TagName, t.Score desc, t.ViewCount desc
limit 100;