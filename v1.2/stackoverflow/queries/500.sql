with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Ancestors
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Ancestors || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on not (t2.Id = any(r.Ancestors))
    where t2.IsModeratorOnly = false and t2.IsRequired = false
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
TopQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null and p.Tags is not null
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(case when a.Score > 0 then 1 end) as PositiveAnswers,
        count(case when a.Score <= 0 then 1 end) as NonPositiveAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseInfo as (
    select
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
),
UserTopBadges as (
    select
        ub.UserId,
        max(case when ub.Class = 1 then ub.BadgeCount else 0 end) as GoldBadges,
        max(case when ub.Class = 2 then ub.BadgeCount else 0 end) as SilverBadges,
        max(case when ub.Class = 3 then ub.BadgeCount else 0 end) as BronzeBadges
    from UserBadgeCounts ub
    group by ub.UserId
),
UserQuestionAnswerStats as (
    select
        u.Id as UserId,
        count(distinct q.Id) as TotalQuestions,
        count(distinct a.Id) as TotalAnswers,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        coalesce(max(a.Score),0) as MaxAnswerScore
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(utb.GoldBadges,0) as GoldBadges,
    coalesce(utb.SilverBadges,0) as SilverBadges,
    coalesce(utb.BronzeBadges,0) as BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    us.TotalQuestions,
    us.TotalAnswers,
    us.TotalAnswerScore,
    us.AvgAnswerScore,
    us.MaxAnswerScore,
    q.Id as TopQuestionId,
    q.Title as TopQuestionTitle,
    q.Score as TopQuestionScore,
    q.ViewCount as TopQuestionViews,
    q.AnswerCount as TopQuestionAnswerCount,
    qc.FirstCloseDate,
    qc.LastReopenDate,
    qc.CloseCount,
    qc.ReopenCount,
    ans.PositiveAnswers,
    ans.NonPositiveAnswers,
    ans.AvgAnswerScore as QuestionAvgAnswerScore,
    ans.MaxAnswerScore as QuestionMaxAnswerScore,
    string_agg(distinct coalesce(t.TagName,'<none>'), ', ') as UserTags
from Users u
left join UserActivityWindow ua on ua.UserId = u.Id
left join UserTopBadges utb on utb.UserId = u.Id
left join UserQuestionAnswerStats us on us.UserId = u.Id
left join TopQuestions q on q.OwnerUserId = u.Id and q.UserTopQuestionRank = 1
left join QuestionCloseInfo qc on qc.PostId = q.Id
left join AnswerStats ans on ans.QuestionId = q.Id
left join lateral (
    select distinct unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) as TagName
) t on true
where u.Reputation > 1000
group by
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    utb.GoldBadges, utb.SilverBadges, utb.BronzeBadges,
    ua.QuestionCount, ua.AnswerCount, ua.CommentCount, ua.UpVotesReceived, ua.DownVotesReceived,
    us.TotalQuestions, us.TotalAnswers, us.TotalAnswerScore, us.AvgAnswerScore, us.MaxAnswerScore,
    q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount,
    qc.FirstCloseDate, qc.LastReopenDate, qc.CloseCount, qc.ReopenCount,
    ans.PositiveAnswers, ans.NonPositiveAnswers, ans.AvgAnswerScore, ans.MaxAnswerScore
order by u.Reputation desc
limit 100;