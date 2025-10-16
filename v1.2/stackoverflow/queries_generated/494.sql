-- {"query": "494.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1792} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 2
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        u.Reputation,
        u.DisplayName,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
AnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        u.Reputation,
        u.DisplayName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionAnswerAggregates as (
    select
        q.QuestionId,
        count(a.AnswerId) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswersCount,
        sum(case when a.Score < 0 then 1 else 0 end) as NegativeAnswersCount
    from QuestionStats q
    left join AnswerStats a on q.QuestionId = a.QuestionId
    group by q.QuestionId
),
BadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.TotalBadges,0) as TotalBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join BadgeSummary b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.GoldBadges, b.SilverBadges, b.BronzeBadges, b.TotalBadges
),
TopQuestionsWithAnswers as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Reputation as OwnerReputation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        qa.TotalAnswers,
        qa.MaxAnswerScore,
        qa.AvgAnswerScore,
        qa.PositiveAnswersCount,
        qa.NegativeAnswersCount,
        u.DisplayName as OwnerDisplayName,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.TotalBadges
    from QuestionStats q
    left join QuestionAnswerAggregates qa on q.QuestionId = qa.QuestionId
    left join UserActivity u on q.OwnerUserId = u.UserId
    where q.Score > 10 and q.AnswerCount > 0
),
DuplicateQuestionLinks as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select
        tqwa.*,
        dq.OriginalQuestionId,
        dq.LinkCreationDate
    from TopQuestionsWithAnswers tqwa
    left join DuplicateQuestionLinks dq on tqwa.QuestionId = dq.DuplicateQuestionId
),
RankedAnswers as (
    select
        a.*,
        row_number() over (partition by a.QuestionId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from AnswerStats a
    where a.Score >= 0
),
FinalSelection as (
    select
        qwd.QuestionId,
        qwd.Title,
        qwd.OwnerUserId,
        qwd.OwnerDisplayName,
        qwd.OwnerReputation,
        qwd.GoldBadges,
        qwd.SilverBadges,
        qwd.BronzeBadges,
        qwd.TotalBadges,
        qwd.QuestionScore,
        qwd.ViewCount,
        qwd.AnswerCount,
        qwd.FavoriteCount,
        qwd.TotalAnswers,
        qwd.MaxAnswerScore,
        qwd.AvgAnswerScore,
        qwd.PositiveAnswersCount,
        qwd.NegativeAnswersCount,
        qwd.OriginalQuestionId,
        qwd.LinkCreationDate,
        ra.AnswerId,
        ra.Score as AnswerScore,
        ra.CreationDate as AnswerCreationDate,
        ra.Reputation as AnswererReputation,
        ra.DisplayName as AnswererDisplayName,
        case
            when qwd.OriginalQuestionId is not null then 'Duplicate'
            else 'Original'
        end as QuestionStatus,
        length(coalesce(qwd.Title, '')) + coalesce(qwd.ViewCount,0) / nullif(qwd.AnswerCount,1) as TitleViewAnswerComplexity,
        concat_ws(' | ',
            qwd.Title,
            coalesce(qwd.OwnerDisplayName, 'Unknown'),
            coalesce(ra.DisplayName, 'NoAnswer'),
            coalesce(qwd.Tags, 'NoTags')
        ) as CompositeStringInfo
    from QuestionsWithDuplicates qwd
    left join RankedAnswers ra on qwd.QuestionId = ra.QuestionId and ra.AnswerRank = 1
    where qwd.QuestionScore > 20 or qwd.TotalAnswers > 5
)
select
    fs.QuestionId,
    fs.Title,
    fs.OwnerUserId,
    fs.OwnerDisplayName,
    fs.OwnerReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.TotalBadges,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.FavoriteCount,
    fs.TotalAnswers,
    fs.MaxAnswerScore,
    round(fs.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    fs.PositiveAnswersCount,
    fs.NegativeAnswersCount,
    fs.OriginalQuestionId,
    fs.LinkCreationDate,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerCreationDate,
    fs.AnswererReputation,
    fs.AnswererDisplayName,
    fs.QuestionStatus,
    fs.TitleViewAnswerComplexity,
    fs.CompositeStringInfo
from FinalSelection fs
order by fs.QuestionScore desc nulls last, fs.TotalAnswers desc nulls last, fs.AnswerScore desc nulls last
limit 100;