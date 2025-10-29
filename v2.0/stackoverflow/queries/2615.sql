-- {"query": "2615.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1921}
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPopularity as (
    select
        t.TagName,
        count(*) as QuestionCount,
        sum(p.Score) as TotalScore,
        avg(p.ViewCount) as AvgViews
    from RecursiveTagCounts t
    join Posts p on p.Id = t.PostId
    group by t.TagName
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserRecentActivity as (
    select
        p.OwnerUserId as UserId,
        max(p.LastActivityDate) as LastActivity,
        count(distinct ph.Id) as EditCountLastYear
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserScoreRanks as (
    select
        UserId,
        TotalPostScore,
        rank() over (order by TotalPostScore desc) as ScoreRank,
        dense_rank() over (order by QuestionCount desc) as QuestionRank,
        dense_rank() over (order by AnswerCount desc) as AnswerRank
    from UserPostStats
),
PostAnswerDetail as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersWithComments as (
    select
        pa.QuestionId,
        pa.Title,
        pa.AnswerId,
        pa.AnswerOwnerId,
        pa.AnswerScore,
        coalesce(c.CommentCount, 0) as CommentsOnAnswer,
        u.DisplayName as AnswerOwnerName,
        us.BadgeCountGold,
        us.BadgeCountSilver,
        us.BadgeCountBronze
    from PostAnswerDetail pa
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = pa.AnswerId
    left join (
        select
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as BadgeCountGold,
            sum(case when Class = 2 then 1 else 0 end) as BadgeCountSilver,
            sum(case when Class = 3 then 1 else 0 end) as BadgeCountBronze
        from Badges
        group by UserId
    ) us on us.UserId = pa.AnswerOwnerId
    left join Users u on u.Id = pa.AnswerOwnerId
    where pa.AnswerRank = 1
),
DuplicateLinkedQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UsersWithDuplicateAnswers as (
    select distinct
        u.Id as UserId,
        u.DisplayName,
        count(distinct pa.QuestionId) as DuplicateAnsweredCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 2
    join DuplicateLinkedQuestions dlq on dlq.DuplicateQuestionId = p.ParentId
    join PostAnswerDetail pa on pa.QuestionId = dlq.OriginalQuestionId and pa.AnswerOwnerId = u.Id
    group by u.Id, u.DisplayName
),
PostsWithCloseInfo as (
    select
        p.Id as PostId,
        p.Title,
        ph.PostHistoryTypeId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1 and ph.Id is not null
),
NewestActiveQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        row_number() over (order by p.LastActivityDate desc NULLS LAST) as rn
    from Posts p
    where p.PostTypeId = 1
)

select
    u.DisplayName as User,
    us.ScoreRank,
    us.QuestionRank,
    us.AnswerRank,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalPostScore,
    coalesce(ub.GoldBadges, 0) as GoldBadges,
    coalesce(ub.SilverBadges, 0) as SilverBadges,
    coalesce(ub.BronzeBadges, 0) as BronzeBadges,
    coalesce(ura.LastActivity, cast('1970-01-01' as timestamp)) as LastActivity,
    coalesce(ura.EditCountLastYear, 0) as EditsLastYear,
    coalesce(dau.DuplicateAnsweredCount, 0) as DuplicateAnsweredQuestions,
    tp.TagName as FavoriteTag,
    tp.QuestionCount as TagQuestions,
    tp.TotalScore as TagScore,
    ta.AnswerScore as TopAnswerScore,
    ta.CommentsOnAnswer as CommentsOnTopAnswer,
    dq.DuplicateTitle as DuplicateQuestionTitle,
    dq.OriginalTitle as OriginalQuestionTitle,
    pci.CloseReason,
    pci.CloseDate
from Users u
join UserPostStats ups on ups.UserId = u.Id
join UserScoreRanks us on us.UserId = u.Id
left join UserBadgeSummary ub on ub.UserId = u.Id
left join UserRecentActivity ura on ura.UserId = u.Id
left join UsersWithDuplicateAnswers dau on dau.UserId = u.Id
left join lateral (
    select tpop.TagName, tpop.QuestionCount, tpop.TotalScore
    from TagPopularity tpop
    join RecursiveTagCounts rtc on rtc.TagName = tpop.TagName
    where rtc.PostId in (select p2.Id from Posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 1)
    group by tpop.TagName, tpop.QuestionCount, tpop.TotalScore, rtc.PostId
    order by tpop.QuestionCount desc NULLS LAST
    limit 1
) tp on true
left join lateral (
    select ta.AnswerScore, ta.CommentsOnAnswer
    from TopAnswersWithComments ta
    where ta.AnswerOwnerId = u.Id
    order by ta.AnswerScore desc NULLS LAST
    limit 1
) ta on true
left join lateral (
    select dq.DuplicateTitle, dq.OriginalTitle
    from DuplicateLinkedQuestions dq
    join Posts p on p.OwnerUserId = u.Id and p.Id = dq.DuplicateQuestionId
    order by dq.DuplicateTitle
    limit 1
) dq on true
left join lateral (
    select pci.CloseReason, pci.CloseDate
    from PostsWithCloseInfo pci
    join Posts p on p.Id = pci.PostId and p.OwnerUserId = u.Id
    order by pci.CloseDate desc NULLS LAST
    limit 1
) pci on true
where us.ScoreRank <= 100
order by us.ScoreRank
limit 100;