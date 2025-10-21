-- {"query": "4048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1563} 
with RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.CreationDate,
        a.Score,
        u.DisplayName as Answerer,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as rn,
        count(*) over (partition by a.ParentId) as total_answers
    from Posts a
    inner join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionStats as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AcceptedAnswerId,
        u.DisplayName as QuestionOwner,
        u.Reputation,
        coalesce(bd.GoldBadges, 0) as GoldBadges,
        coalesce(bd.SilverBadges, 0) as SilverBadges,
        coalesce(bd.BronzeBadges, 0) as BronzeBadges,
        (select count(*) from Comments c where c.PostId = q.Id and c.UserId is not null) as CommentsCount,
        case
            when q.ClosedDate is null then 'Open'
            else 'Closed'
        end as Status,
        dense_rank() over (order by q.Score desc) as ScoreRank
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join (
        select
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) bd on u.Id = bd.UserId
    where q.PostTypeId = 1
),
CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotes
    from PostHistory ph
    inner join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
QuestionAnswerDetails as (
    select
        qs.Id as QuestionId,
        qs.Title,
        qs.Tags,
        qs.QuestionScore,
        qs.ViewCount,
        qs.QuestionOwner,
        qs.Reputation,
        qs.GoldBadges,
        qs.SilverBadges,
        qs.BronzeBadges,
        qs.CommentsCount,
        qs.Status,
        qs.ScoreRank,
        ra.Id as AnswerId,
        ra.Score as AnswerScore,
        ra.CreationDate as AnswerDate,
        ra.Answerer,
        ra.rn as AnswerRank,
        ra.total_answers,
        cr.CloseReason,
        cr.CloseVotes
    from QuestionStats qs
    left join RankedAnswers ra on qs.Id = ra.ParentId and ra.rn <= 3
    left join CloseReasonsCount cr on qs.Id = cr.PostId
    where qs.ScoreRank between 1 and 1000
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(qc.QuestionCount, 0) as QuestionsPosted,
        coalesce(ac.AnswerCount, 0) as AnswersPosted,
        coalesce(vc.UpVotes, 0) as TotalUpVotes,
        coalesce(vc.DownVotes, 0) as TotalDownVotes,
        coalesce(bd.TotalBadges, 0) as BadgeCount,
        case 
            when u.LastAccessDate > now() - interval '30 days' then 1
            else 0
        end as ActiveLast30Days,
        -- Average answer score per user, excluding deleted posts
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2 and p.Score is not null) as AvgAnswerScore
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) qc on u.Id = qc.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) ac on u.Id = ac.OwnerUserId
    left join (
        select v.UserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        where v.UserId is not null
        group by v.UserId
    ) vc on u.Id = vc.UserId
    left join (
        select UserId, count(*) as TotalBadges
        from Badges
        group by UserId
    ) bd on u.Id = bd.UserId
),
TagPopularity as (
    select
        unnest(string_to_array(substring(t.Tags from 2 for length(t.Tags)-2), '><')) as TagName,
        count(*) as UsageCount,
        avg(t.Score) as AvgScore
    from Posts t
    where t.PostTypeId = 1 and t.Tags is not null
    group by TagName
),
TopTags as (
    select TagName, UsageCount, AvgScore,
    rank() over (order by UsageCount desc) as TagRank
    from TagPopularity
    where UsageCount > 1000
)
select
    qad.QuestionId,
    qad.Title,
    qad.Tags,
    qad.QuestionScore,
    qad.ViewCount,
    qad.QuestionOwner,
    qad.Reputation,
    qad.GoldBadges,
    qad.SilverBadges,
    qad.BronzeBadges,
    qad.CommentsCount,
    qad.Status,
    coalesce(qad.CloseReason, 'N/A') as CloseReason,
    coalesce(qad.CloseVotes, 0) as CloseVotes,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerDate,
    qa.Answerer,
    qa.AnswerRank,
    qa.total_answers,
    ua.DisplayName as ActiveUser,
    ua.Reputation as UserReputation,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.BadgeCount,
    ua.ActiveLast30Days,
    ua.AvgAnswerScore,
    tt.TagName as PopularTag,
    tt.UsageCount as PopularTagUsage,
    tt.AvgScore as PopularTagAvgScore
from QuestionAnswerDetails qad
left join QuestionAnswerDetails qa on qad.QuestionId = qa.QuestionId and qa.AnswerRank = 1
left join UserActivity ua on ua.Id = qad.QuestionOwner
left join TopTags tt on tt.TagName = any(string_to_array(substring(qad.Tags from 2 for length(qad.Tags)-2), '><'))
where coalesce(qa.AnswerScore, 0) >= 5 and ua.ActiveLast30Days = 1
order by qad.ScoreRank, qa.AnswerScore desc
limit 100;