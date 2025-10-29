-- {"query": "2283.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1457}
with RecentTopUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        dense_rank() over (order by u.Reputation desc, u.CreationDate asc) as RankByRep,
        count(distinct b.Id) as BadgeCount,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '5 years')
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
UserQuestionStats as (
    select 
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(*) filter (where p.PostTypeId = 2) as AnswersGiven,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
UserRecentActivity as (
    select 
        ph.UserId,
        max(ph.CreationDate) as LastEditDate,
        count(*) as TotalEdits,
        count(distinct ph.PostId) as EditedPostsCount,
        sum(case when ph.PostHistoryTypeId in (10,11) then 1 else 0 end) as CloseReopenVotes
    from PostHistory ph
    where ph.UserId is not null
    group by ph.UserId
),
UserCommentsAgg as (
    select 
        c.UserId,
        count(c.Id) as CommentCount,
        avg(c.Score) as AvgCommentScore,
        max(c.Score) as MaxCommentScore
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserPostLinks as (
    select 
        pl.PostId as UserPostId,
        count(distinct pl.RelatedPostId) as LinkedPostsCount,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinksCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionWithAcceptedAnswer as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AnswerDate,
        u.DisplayName as QuestionOwner,
        au.DisplayName as AnswerOwner,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionCommentCount,
        (select count(*) from Comments c where c.PostId = coalesce(q.AcceptedAnswerId, 0)) as AnswerCommentCount,
        case when q.ClosedDate is null then false else true end as IsClosed,
        q.Tags,
        q.OwnerUserId
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on q.OwnerUserId = u.Id
    left join Users au on a.OwnerUserId = au.Id
    where q.PostTypeId = 1
),
TaggedQuestions as (
    select 
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as Tag
    from QuestionWithAcceptedAnswer q
),
TagStats as (
    select 
        t.Tag,
        count(distinct q.QuestionId) as QuestionCount,
        avg(q.QuestionScore) as AvgQuestionScore,
        avg(q.AcceptedAnswerScore) as AvgAcceptedAnswerScore,
        sum(case when q.IsClosed then 1 else 0 end) as ClosedQuestions,
        sum(q.ViewCount) as TotalViews
    from TaggedQuestions t
    join QuestionWithAcceptedAnswer q on q.QuestionId = t.QuestionId
    group by t.Tag
),
TopTags as (
    select 
        Tag,
        QuestionCount,
        AvgQuestionScore,
        AvgAcceptedAnswerScore,
        ClosedQuestions,
        TotalViews,
        row_number() over (order by QuestionCount desc) as TagRank
    from TagStats
    where QuestionCount > 1000
    order by QuestionCount desc
    limit 20
),
UserFiltered as (
    select u.Id, u.DisplayName, u.Reputation, u.Location from RecentTopUsers u
    where u.RankByRep <= 1000
)
select 
    uf.DisplayName as UserName,
    uf.Reputation,
    uf.Location,
    uqs.QuestionsAsked,
    uqs.AnswersGiven,
    round(cast(uqs.AvgQuestionScore as numeric),2) as AvgQuestionScore,
    round(cast(uqs.AvgAnswerScore as numeric),2) as AvgAnswerScore,
    ur.LastEditDate,
    ur.TotalEdits,
    uc.CommentCount,
    uc.AvgCommentScore,
    ts.Tag as FavoriteTag,
    ts.QuestionCount as FavoriteTagQCount,
    ts.AvgQuestionScore as FavoriteTagAvgQScore,
    ts.AvgAcceptedAnswerScore as FavoriteTagAvgAScore
from UserFiltered uf
left join UserQuestionStats uqs on uqs.UserId = uf.Id
left join UserRecentActivity ur on ur.UserId = uf.Id
left join UserCommentsAgg uc on uc.UserId = uf.Id
left join lateral (
    select 
        t.Tag, t.QuestionCount, t.AvgQuestionScore, t.AvgAcceptedAnswerScore
    from (
        select Tag, count(*) as cnt from TaggedQuestions tq
        join Posts p on tq.QuestionId = p.Id
        where p.OwnerUserId = uf.Id
        group by Tag
    ) userTags
    join TagStats t on t.Tag = userTags.Tag
    order by userTags.cnt desc
    limit 1
) ts on true
where uf.Location is not null
group by
    uf.DisplayName,
    uf.Reputation,
    uf.Location,
    uqs.QuestionsAsked,
    uqs.AnswersGiven,
    uqs.AvgQuestionScore,
    uqs.AvgAnswerScore,
    ur.LastEditDate,
    ur.TotalEdits,
    uc.CommentCount,
    uc.AvgCommentScore,
    ts.Tag,
    ts.QuestionCount,
    ts.AvgQuestionScore,
    ts.AvgAcceptedAnswerScore,
    uf.Id
order by uf.Reputation desc, uf.DisplayName asc
fetch first 100 rows only;