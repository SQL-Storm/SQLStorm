-- {"query": "717.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1271} 
with RecursiveUserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        coalesce(pq.QuestionCount,0) as QuestionCount,
        coalesce(pa.AnswerCount,0) as AnswerCount,
        coalesce(c.CommentCount,0) as CommentCount,
        row_number() over (order by u.Reputation desc nulls last, u.Id) as UserRank
    from Users u
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) pq on u.Id = pq.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) pa on u.Id = pa.OwnerUserId
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        group by UserId
    ) c on u.Id = c.UserId
    where u.Reputation > 1000
),
TopTags AS (
    select
        t.TagName,
        t.Count,
        coalesce(ptp.QuestionCount,0) as Questions,
        coalesce(ptp.AnswerCount,0) as Answers,
        dense_rank() over (order by t.Count desc) as TagRank
    from Tags t
    left join (
        select 
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
            sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount
        from Posts p
        where p.Tags is not null
        group by unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'))
    ) ptp on t.TagName = ptp.TagName
    where t.TagName is not null
),
QuestionsWithAnswers AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
QuestionsWithTopAnswers AS (
    select *
    from QuestionsWithAnswers
    where AnswerRank = 1
),
UserBadgeSummary AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
CloseReasonCounts AS (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$' -- only numeric close reason IDs
    group by cht.Name
),
DuplicateQuestions AS (
    select distinct q.Id as QuestionId, q.Title, pl.CreationDate as LinkCreationDate, lp.Id as LinkedPostId
    from Posts q
    join PostLinks pl on q.Id = pl.PostId and pl.LinkTypeId = 3
    join Posts lp on pl.RelatedPostId = lp.Id and lp.PostTypeId = 1
    where q.PostTypeId = 1
),
FinalResult AS (
    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.Location,
        r.Views,
        r.BadgeCount,
        r.QuestionCount,
        r.AnswerCount,
        r.CommentCount,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        qta.QuestionId,
        qta.Title as TopQuestionTitle,
        qta.QuestionScore,
        qta.ViewCount as QuestionViews,
        qta.AnswerId,
        qta.AnswerScore,
        qta.AnswerCreationDate,
        qta.AnswerOwnerUserId,
        crc.CloseReason,
        crc.CloseCount,
        dt.LinkedPostId as DuplicateOfQuestionId,
        dt.LinkCreationDate
    from RecursiveUserActivity r
    left join UserBadgeSummary ubs on r.UserId = ubs.UserId
    left join QuestionsWithTopAnswers qta on qta.OwnerUserId = r.UserId
    left join CloseReasonCounts crc on crc.CloseReason is not null
    left join DuplicateQuestions dt on dt.QuestionId = qta.QuestionId
    where r.UserRank <= 50
)
select *
from FinalResult
order by Reputation desc nulls last, QuestionScore desc nulls last, AnswerScore desc nulls last
limit 100;