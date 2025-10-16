-- {"query": "945.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1370} 
with RECURSIVE UserBadgeCounts AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
), LatestAnswers AS (
    select
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
), QuestionAnswerStats AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        coalesce(ans.AnswerCount,0) as TotalAnswers,
        coalesce(la.AnswerRank,0) as TopAnswerRank,
        la.Id as TopAnswerId,
        la.Score as TopAnswerScore,
        la.OwnerUserId as TopAnswerOwner
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on q.Id = ans.ParentId
    left join LatestAnswers la on q.Id = la.ParentId and la.AnswerRank = 1
    where q.PostTypeId = 1
), QuestionWithCloseDetails AS (
    select
        qas.*,
        ph.Comment as CloseReason,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from QuestionAnswerStats qas
    left join PostHistory ph on ph.PostId = qas.QuestionId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
), QuestionsRanked AS (
    select
        *,
        rank() over (partition by Tags order by QuestionScore desc, ViewCount desc) as TagRank,
        dense_rank() over (order by TotalAnswers desc, QuestionScore desc) as PopularityRank
    from QuestionWithCloseDetails
), UserParticipation AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        sum(vt.Name = 'UpMod'::varchar::text::varchar) as UpVotesReceived,
        sum(vt.Name = 'DownMod'::varchar::text::varchar) as DownVotesReceived,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName
), UserRanks AS (
    select
        up.*,
        row_number() over (order by PostsCount desc, AnswersCount desc, QuestionsCount desc) as OverallRank
    from UserParticipation up
), CombinedResults AS (
    select
        qr.QuestionId,
        qr.Title,
        qr.Tags,
        qr.QuestionOwner,
        ubd.DisplayName as QuestionOwnerName,
        qr.QuestionScore,
        qr.ViewCount,
        qr.TotalAnswers,
        qr.TopAnswerId,
        qr.TopAnswerScore,
        qr.TopAnswerOwner,
        ubd2.DisplayName as TopAnswerOwnerName,
        qr.CloseReasonName,
        qr.CloseDate,
        qr.TagRank,
        qr.PopularityRank,
        ur.OverallRank as QuestionOwnerRank,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges
    from QuestionsRanked qr
    left join Users ubd on ubd.Id = qr.QuestionOwner
    left join Users ubd2 on ubd2.Id = qr.TopAnswerOwner
    left join UserRanks ur on ur.UserId = qr.QuestionOwner
    left join UserBadgeCounts ubc on ubc.UserId = qr.QuestionOwner
    where qr.CloseReasonName is null or qr.CloseReasonName <> 'Duplicate'
)
select cr.*,
    -- complex string manipulation: normalized tags list, replace '><' with ', '
    replace(
        replace(
            substring(cr.Tags from 2 for length(cr.Tags) - 2)
        , '><', ', ')
    , '&lt;', '<') as NormalizedTags,
    -- calculate age of question in days, with null logic
    coalesce(
        extract(epoch from (greatest(coalesce(cr.CloseDate, now()), now()) - cr.QuestionScore::timestamp)) / 86400
    , null) as QuestionAgeDays,
    -- boolean logic to determine popular and active
    case
        when cr.TotalAnswers > 5 and cr.ViewCount > 10000 and cr.QuestionScore > 20 then 'Highly Popular'
        when cr.TotalAnswers between 1 and 5 and cr.ViewCount between 1000 and 10000 then 'Moderately Popular'
        else 'Less Popular'
    end as PopularityCategory,
    -- use nullsafe coalesce to check badge counts and rank
    case
        when coalesce(cr.GoldBadges,0) > 0 then 'Gold Badge Holder'
        when coalesce(cr.SilverBadges,0) > 5 then 'Silver Badge Expert'
        when coalesce(cr.BronzeBadges,0) > 10 then 'Bronze Badge Accumulator'
        else 'No Significant Badges'
    end as BadgeStatus
from CombinedResults cr
where cr.QuestionScore > 0
order by cr.TagRank, cr.PopularityRank, cr.QuestionAgeDays desc
limit 100;