with recursive RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        rtc.TotalAnswers + coalesce(p.AnswerCount, 0) as TotalAnswers,
        rtc.TotalViews + coalesce(p.ViewCount, 0) as TotalViews
    from Tags t
    join RecursiveTagCounts rtc on t.Id = rtc.Id
    left join Posts p on p.Id = t.WikiPostId and p.PostTypeId = 1
    where rtc.TotalAnswers < 100000
),
UserBadgeRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class
),
TopUsers as (
    select
        UserId,
        DisplayName,
        coalesce(sum(case when Class = 1 then BadgeCount else 0 end), 0) as GoldBadges,
        coalesce(sum(case when Class = 2 then BadgeCount else 0 end), 0) as SilverBadges,
        coalesce(sum(case when Class = 3 then BadgeCount else 0 end), 0) as BronzeBadges,
        row_number() over (
            order by
                sum(case when Class = 1 then BadgeCount else 0 end) desc,
                sum(case when Class = 2 then BadgeCount else 0 end) desc,
                sum(case when Class = 3 then BadgeCount else 0 end) desc
        ) as Rank
    from UserBadgeRanks
    group by UserId, DisplayName
    having sum(case when Class = 1 then BadgeCount else 0 end) > 0
),
PostScoreStats as (
    select
        p.OwnerUserId,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        count(*) as PostCount
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ps.AvgScore, 0) as AveragePostScore,
        coalesce(ps.MaxScore, 0) as MaxPostScore,
        coalesce(ps.MinScore, 0) as MinPostScore,
        coalesce(ps.PostCount, 0) as TotalPosts,
        coalesce(v.UpVotes, 0) as TotalUpVotes,
        coalesce(v.DownVotes, 0) as TotalDownVotes,
        coalesce(b.GoldBadges, 0) as GoldBadges,
        coalesce(b.SilverBadges, 0) as SilverBadges,
        coalesce(b.BronzeBadges, 0) as BronzeBadges
    from Users u
    left join PostScoreStats ps on ps.OwnerUserId = u.Id
    left join (
        select
            UserId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        where UserId is not null
        group by UserId
    ) v on v.UserId = u.Id
    left join TopUsers b on b.UserId = u.Id
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        a.Id as AnswerId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
TopAnswers as (
    select
        QuestionId,
        Title,
        QuestionDate,
        QuestionScore,
        QuestionViews,
        AnswerId,
        AnswerDate,
        AnswerScore,
        AnswerOwner,
        AnswerOwnerName
    from QuestionAnswerStats
    where AnswerRank = 1
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId,
        u.DisplayName as OwnerName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = p.OwnerUserId
    where ph.PostHistoryTypeId = 10
),
UserCloseStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct cq.PostId) as ClosedQuestionsCount,
        max(cq.CloseDate) as LastClosedDate
    from Users u
    left join ClosedQuestions cq on cq.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
FinalResult as (
    select
        ua.Id as UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.AveragePostScore,
        ua.MaxPostScore,
        ua.MinPostScore,
        ua.TotalPosts,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ucs.ClosedQuestionsCount,
        ucs.LastClosedDate,
        ta.QuestionId,
        ta.Title as TopQuestionTitle,
        ta.QuestionDate,
        ta.QuestionScore,
        ta.QuestionViews,
        ta.AnswerId as TopAnswerId,
        ta.AnswerDate as TopAnswerDate,
        ta.AnswerScore as TopAnswerScore,
        ta.AnswerOwner as TopAnswerOwnerId,
        ta.AnswerOwnerName as TopAnswerOwnerName
    from UserActivity ua
    left join UserCloseStats ucs on ucs.UserId = ua.Id
    left join TopAnswers ta on ta.AnswerOwner = ua.Id
    where ua.TotalPosts > 10
)
select
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.CreationDate,
    fr.LastAccessDate,
    fr.AveragePostScore,
    fr.MaxPostScore,
    fr.MinPostScore,
    fr.TotalPosts,
    fr.TotalUpVotes,
    fr.TotalDownVotes,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.ClosedQuestionsCount,
    fr.LastClosedDate,
    fr.TopQuestionTitle,
    fr.QuestionDate,
    fr.QuestionScore,
    fr.QuestionViews,
    fr.TopAnswerId,
    fr.TopAnswerDate,
    fr.TopAnswerScore,
    fr.TopAnswerOwnerName,
    case
        when fr.Reputation > 10000 and fr.GoldBadges > 5 then 'Elite User'
        when fr.Reputation between 1000 and 10000 then 'Experienced User'
        else 'New User'
    end as UserCategory,
    concat_ws(' | ',
        coalesce(fr.DisplayName, 'Anonymous'),
        'Reputation: ' || cast(fr.Reputation as varchar),
        'Posts: ' || cast(fr.TotalPosts as varchar),
        'Badges (G/S/B): ' || cast(fr.GoldBadges as varchar) || '/' || cast(fr.SilverBadges as varchar) || '/' || cast(fr.BronzeBadges as varchar),
        coalesce(fr.TopQuestionTitle, 'No Top Question'),
        coalesce(fr.TopAnswerOwnerName, 'No Top Answer')
    ) as UserSummary
from FinalResult fr
order by fr.Reputation desc, fr.GoldBadges desc, fr.TotalPosts desc
limit 100;