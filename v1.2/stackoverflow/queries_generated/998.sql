-- {"query": "998.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1519} 
with RecentActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    where u.LastAccessDate > current_date - interval '180 days'
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserQuestionStats as (
    select
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews,
        max(p.CreationDate) filter (where p.PostTypeId = 1) as LastQuestionDate
    from Posts p
    group by p.OwnerUserId
),
UserAnswerStats as (
    select
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        sum(case when p.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerCount
    from Posts p
    left join Posts q on q.AcceptedAnswerId = p.Id and q.PostTypeId = 1
    group by p.OwnerUserId
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserPostHistoryEdits as (
    select
        ph.UserId,
        count(distinct ph.PostId) as EditedPostCount,
        count(*) as TotalEdits,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.UserId is not null
    group by ph.UserId
),
TopTags as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(t.IsModeratorOnly, 0) as IsModeratorOnly,
        coalesce(t.IsRequired, 0) as IsRequired
    from Tags t
    where t.Count > 1000
),
UserTopTagUsage as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
UserPopularTagCounts as (
    select
        utu.UserId,
        ut.TagName,
        count(*) as QuestionsWithTag
    from UserTopTagUsage utu
    join TopTags ut on ut.TagName = utu.TagName
    group by utu.UserId, ut.TagName
),
UserMostUsedTag as (
    select distinct on (UserId)
        UserId,
        TagName,
        QuestionsWithTag
    from UserPopularTagCounts
    order by UserId, QuestionsWithTag desc
),
UserActivitySummary as (
    select
        ra.Id as UserId,
        ra.DisplayName,
        ra.Reputation,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
        coalesce(uqs.QuestionCount, 0) as QuestionCount,
        coalesce(uqs.AvgQuestionScore, 0) as AvgQuestionScore,
        coalesce(uqs.TotalQuestionViews, 0) as TotalQuestionViews,
        coalesce(uas.AnswerCount, 0) as AnswerCount,
        coalesce(uas.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(uas.AcceptedAnswerCount, 0) as AcceptedAnswerCount,
        coalesce(ucs.CommentCount, 0) as CommentCount,
        coalesce(ucs.AvgCommentLength, 0) as AvgCommentLength,
        coalesce(uph.EditedPostCount, 0) as EditedPostCount,
        coalesce(uph.TotalEdits, 0) as TotalEdits,
        coalesce(umt.TagName, 'None') as MostUsedTag,
        coalesce(umt.QuestionsWithTag, 0) as MostUsedTagQuestionCount
    from RecentActiveUsers ra
    left join UserBadgeStats ubs on ra.Id = ubs.UserId
    left join UserQuestionStats uqs on ra.Id = uqs.UserId
    left join UserAnswerStats uas on ra.Id = uas.UserId
    left join UserCommentStats ucs on ra.Id = ucs.UserId
    left join UserPostHistoryEdits uph on ra.Id = uph.UserId
    left join UserMostUsedTag umt on ra.Id = umt.UserId
),
UserPerformanceRankings as (
    select
        uas.*,
        rank() over (order by (GoldBadges * 10 + SilverBadges * 5 + BronzeBadges * 2 + Reputation/500 + AcceptedAnswerCount * 3 + AnswerCount + QuestionCount * 0.5) desc) as PerformanceRank
    from UserActivitySummary uas
)
select
    upr.PerformanceRank,
    upr.UserId,
    upr.DisplayName,
    upr.Reputation,
    upr.GoldBadges,
    upr.SilverBadges,
    upr.BronzeBadges,
    upr.QuestionCount,
    round(upr.AvgQuestionScore::numeric,2) as AvgQuestionScore,
    upr.TotalQuestionViews,
    upr.AnswerCount,
    round(upr.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    upr.AcceptedAnswerCount,
    upr.CommentCount,
    round(upr.AvgCommentLength::numeric,1) as AvgCommentLength,
    upr.EditedPostCount,
    upr.TotalEdits,
    upr.MostUsedTag,
    upr.MostUsedTagQuestionCount,
    case
        when upr.LastAccessDate < current_date - interval '30 days' then 'Inactive'
        else 'Active'
    end as UserActivityStatus
from UserPerformanceRankings upr
join Users u on upr.UserId = u.Id
order by upr.PerformanceRank asc
limit 100;