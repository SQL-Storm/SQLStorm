-- {"query": "401.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1631} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        rth.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy rth on t2.Id <> all(rth.Path)
    where t2.Count > 1000 and not (t2.Id = any(rth.Path))
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(avg(p.Score), 0) as AvgPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersWithComments as (
    select
        qa.QuestionId,
        qa.Title,
        qa.OwnerUserId,
        qa.QuestionCreationDate,
        qa.QuestionScore,
        qa.ViewCount,
        qa.Tags,
        qa.AnswerId,
        qa.AnswerOwnerUserId,
        qa.AnswerCreationDate,
        qa.AnswerScore,
        c.CommentCount,
        c.TopCommentText,
        u.DisplayName as AnswerOwnerDisplayName,
        u.Reputation as AnswerOwnerReputation
    from QuestionAnswerStats qa
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(Text) filter (where length(Text) = (select max(length(Text)) from Comments c2 where c2.PostId = Comments.PostId)) as TopCommentText
        from Comments
        group by PostId
    ) c on c.PostId = qa.AnswerId
    left join Users u on u.Id = qa.AnswerOwnerUserId
    where qa.AnswerRank = 1
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsInLast30Days,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as QuestionsInLast30Days,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as AnswersInLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(*) filter (where lt.Name = 'Linked') as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    group by ph.PostId, crt.Name
),
FinalResults as (
    select
        tas.QuestionId,
        tas.Title,
        tas.OwnerUserId,
        u.DisplayName as QuestionOwner,
        tas.QuestionCreationDate,
        tas.QuestionScore,
        tas.ViewCount,
        tas.Tags,
        tas.AnswerId,
        tas.AnswerOwnerUserId,
        tas.AnswerOwnerDisplayName,
        tas.AnswerCreationDate,
        tas.AnswerScore,
        tas.CommentCount,
        tas.TopCommentText,
        tas.AnswerOwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalPostScore,
        ub.AvgPostScore,
        ub.LastPostDate,
        dac.DuplicateCount,
        dac.LinkedCount,
        crc.CloseReasonName,
        crc.CloseVotesCount,
        uact.PostsInLast30Days,
        uact.QuestionsInLast30Days,
        uact.AnswersInLast30Days,
        length(tas.Title) as TitleLength,
        case
            when tas.AnswerScore > tas.QuestionScore then 'AnswerBetter'
            when tas.AnswerScore = tas.QuestionScore then 'Tie'
            else 'QuestionBetter'
        end as ScoreComparison,
        coalesce(nullif(tas.Tags, ''), '<no-tags>') as TagsNormalized,
        case when ub.GoldBadges > 0 then 'Experienced' else 'Novice' end as UserExperienceLevel
    from TopAnswersWithComments tas
    left join Users u on u.Id = tas.OwnerUserId
    left join UserBadgeStats ub on ub.UserId = tas.AnswerOwnerUserId
    left join DuplicateLinkCounts dac on dac.PostId = tas.QuestionId
    left join CloseReasonCounts crc on crc.PostId = tas.QuestionId
    left join UserActivityWindow uact on uact.UserId = tas.AnswerOwnerUserId and uact.PostId = tas.AnswerId
    where tas.QuestionScore > 5 and tas.AnswerScore is not null
)
select
    QuestionId,
    Title,
    QuestionOwner,
    QuestionCreationDate,
    QuestionScore,
    ViewCount,
    TagsNormalized,
    AnswerId,
    AnswerOwnerUserId,
    AnswerOwnerDisplayName,
    AnswerCreationDate,
    AnswerScore,
    CommentCount,
    substring(TopCommentText from 1 for 100) as TopCommentSnippet,
    AnswerOwnerReputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalPostScore,
    round(AvgPostScore::numeric,2) as AvgPostScore,
    LastPostDate,
    DuplicateCount,
    LinkedCount,
    CloseReasonName,
    CloseVotesCount,
    PostsInLast30Days,
    QuestionsInLast30Days,
    AnswersInLast30Days,
    TitleLength,
    ScoreComparison,
    UserExperienceLevel
from FinalResults
order by QuestionScore desc, AnswerScore desc
limit 100;