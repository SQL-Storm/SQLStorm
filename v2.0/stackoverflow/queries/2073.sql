with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        1 as Level,
        cast(null as int) as ParentTagId
    from Tags t
    where t.IsRequired = true

    union all

    select
        child.Id,
        child.TagName,
        parent.Level + 1,
        parent.Id
    from Tags child
    join RecursiveTagHierarchy parent on position(parent.TagName in child.TagName) = 1
    where child.Id <> parent.Id and child.IsRequired = true
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        coalesce(sum(vt.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes), 0) as TotalDownVotes,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    left join Comments c on c.UserId = u.Id and c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    left join (
        select
            p.OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    where u.Reputation > 500
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoreStats as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.Title,
        avg(p.Score) over (partition by p.PostTypeId order by p.CreationDate rows between 30 preceding and current row) as MovingAvgScore,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank
    from Posts p
    where p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        p.OwnerUserId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(crt.Id as varchar) = ph.Comment
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10
),
TopUsersByActivity as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.ReputationRank,
        ua.Reputation,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.CommentsCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.TotalUpVotes - ua.TotalDownVotes as VoteScore
    from UserActivity ua
    left join (
        select
            UserId,
            coalesce(max(case when Class = 1 then BadgeCount else 0 end),0) as GoldBadges,
            coalesce(max(case when Class = 2 then BadgeCount else 0 end),0) as SilverBadges,
            coalesce(max(case when Class = 3 then BadgeCount else 0 end),0) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) ub on ub.UserId = ua.UserId
    where ua.ReputationRank <= 100
)
select
    tu.DisplayName as User,
    tu.Reputation,
    tu.QuestionsCount,
    tu.AnswersCount,
    tu.CommentsCount,
    (tu.GoldBadges || ' Gold / ' || tu.SilverBadges || ' Silver / ' || tu.BronzeBadges || ' Bronze') as Badges,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    tu.VoteScore,
    pq.Id as TopPostId,
    pq.Title as TopPostTitle,
    pq.Score as TopPostScore,
    pq.MovingAvgScore,
    cq.Title as RecentlyClosedQuestion,
    cq.CloseReason,
    cq.CloseDate,
    array_agg(distinct rth.TagName) filter (where rth.Level <= 2) as RelatedRequiredTags
from TopUsersByActivity tu
left join lateral (
    select
        p.Id,
        p.Title,
        p.Score,
        p.MovingAvgScore,
        p.Tags
    from PostScoreStats p
    where p.OwnerUserId = tu.UserId and p.PostTypeId = 1
    order by p.Score desc nulls last
    limit 1
) pq on true
left join lateral (
    select
        cq.Title,
        cq.CloseReason,
        cq.CloseDate,
        cq.OwnerUserId
    from ClosedQuestionsWithReasons cq
    where cq.OwnerUserId = tu.UserId
    order by cq.CloseDate desc
    limit 1
) cq on true
left join RecursiveTagHierarchy rth on position(('<' || rth.TagName || '>') in coalesce(pq.Tags, '')) > 0
group by
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionsCount,
    tu.AnswersCount,
    tu.CommentsCount,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    tu.VoteScore,
    pq.Id,
    pq.Title,
    pq.Score,
    pq.MovingAvgScore,
    cq.Title,
    cq.CloseReason,
    cq.CloseDate
order by tu.Reputation desc, tu.VoteScore desc;