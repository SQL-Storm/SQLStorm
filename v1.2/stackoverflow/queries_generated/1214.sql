-- {"query": "1214.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1808} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        array[t.Id] as Path,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0

    union all

    select 
        c.Id,
        c.TagName,
        r.Path || c.Id,
        r.Level + 1
    from Tags c
    join RecursiveTagHierarchy r on c.Id != all(r.Path)
    where c.IsModeratorOnly = 0 and r.Level < 3
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(case when b.TagBased = 1 then 1 end) as TagBasedBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.CreationDate as QuestionCreation,
        q.Tags,
        q.ViewCount,
        q.Score as QuestionScore,
        (select count(*) from Posts a where a.ParentId = q.Id) as AnswerCount,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCountQuestion,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotesQuestion,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotesQuestion,
        coalesce(q.AcceptedAnswerId, -1) as AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1
),
AnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        vcounts.UpVotesAnswer,
        vcounts.DownVotesAnswer,
        row_number() over(partition by a.ParentId order by a.Score desc, a.CreationDate) as AnswerRank,
        case when a.Id = qas.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    join QuestionAnswerStats qas on a.ParentId = qas.QuestionId
    left join Users u on a.OwnerUserId = u.Id
    left join (
        select 
            v.PostId,
            count(case when v.VoteTypeId = 2 then 1 end) as UpVotesAnswer,
            count(case when v.VoteTypeId = 3 then 1 end) as DownVotesAnswer
        from Votes v
        where v.PostId is not null
        group by v.PostId
    ) vcounts on vcounts.PostId = a.Id
    where a.PostTypeId = 2
),
QuestionWithAnswers as (
    select 
        qas.*,
        array_agg(json_build_object(
            'AnswerId', ad.AnswerId,
            'AnswerScore', ad.AnswerScore,
            'OwnerUserId', ad.OwnerUserId,
            'OwnerDisplayName', ad.OwnerDisplayName,
            'UpVotes', coalesce(ad.UpVotesAnswer, 0),
            'DownVotes', coalesce(ad.DownVotesAnswer, 0),
            'AnswerRank', ad.AnswerRank,
            'IsAccepted', ad.IsAccepted
        ) order by ad.AnswerRank) as AnswersDetails
    from QuestionAnswerStats qas
    left join AnswerDetails ad on ad.QuestionId = qas.QuestionId
    group by qas.QuestionId, qas.Title, qas.CreationDate, qas.Tags, qas.ViewCount, qas.Score, qas.AcceptedAnswerId, qas.AnswerCount, qas.CommentCountQuestion, qas.UpVotesQuestion, qas.DownVotesQuestion
),
TagPopularity as (
    select
        tag.Type as TagName,
        count(p.Id) as PostCount,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews
    from Posts p
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag(Type)
    group by tag.Type
    having count(p.Id) > 10
),
ActiveUsers as (
    select
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(b.Id) as BadgesCount,
        coalesce(sum(vcount.VotesReceived),0) as TotalVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id AND p.DeletionDate IS NULL
    left join Badges b on b.UserId = u.Id
    left join (
        select p2.OwnerUserId, count(v.Id) as VotesReceived
        from Posts p2 
        left join Votes v on v.PostId = p2.Id and v.VoteTypeId in (2,3)
        where p2.OwnerUserId is not null
        group by p2.OwnerUserId
    ) vcount on vcount.OwnerUserId = u.Id
    where u.Reputation > 1000 and u.LastAccessDate > (now() - interval '6 months')
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
DuplicateQuestionLinks as (
    select pl.PostId as DuplicatePostId,
           pl.RelatedPostId as OriginalPostId,
           pq.Title as DuplicateTitle,
           po.Title as OriginalTitle,
           pl.CreationDate as LinkCreated
    from PostLinks pl
    join Posts pq on pq.Id = pl.PostId and pq.PostTypeId = 1
    join Posts po on po.Id = pl.RelatedPostId and po.PostTypeId = 1 
    where pl.LinkTypeId = 3
),
CTEFinalSummary as (
    select 
        t.TagName,
        tp.PostCount,
        tp.AvgScore,
        tp.TotalViews,
        au.QuestionsCount,
        au.AnswersCount,
        au.BadgesCount,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.TagBasedBadges,
        (select count(*) from DuplicateQuestionLinks dql where dql.OriginalPostId in (
             select q.QuestionId from QuestionWithAnswers q where string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><') @> array[t.TagName]
         )) as DuplicatePostsCount,
        (select max(Score) from Posts p where p.PostTypeId = 1 and string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') @> array[t.TagName]) as HighestScoreQuestion
    from TagPopularity tp
    join LATERAL (select t.TagName) t on true
    left join ActiveUsers au on au.Id = (select Id from Users order by random() limit 1)
    left join UserBadgeStats ubs on ubs.UserId = au.Id
    limit 15
)
select 
    TagName,
    PostCount,
    round(AvgScore,2) as AvgScore,
    TotalViews,
    QuestionsCount,
    AnswersCount,
    BadgesCount,
    GoldBadges * 1.0 / nullif(PostCount,0) as GoldBadgePerPostRatio,
    SilverBadges * 1.0 / nullif(PostCount,0) as SilverBadgePerPostRatio,
    BronzeBadges * 1.0 / nullif(PostCount,0) as BronzeBadgePerPostRatio,
    TagBasedBadges,
    DuplicatePostsCount,
    HighestScoreQuestion
from CTEFinalSummary
order by TotalViews desc, AvgScore desc
limit 10;