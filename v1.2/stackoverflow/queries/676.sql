-- {"query": "676.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1886} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        ph.CreationDate as LastEditDate,
        ph.PostHistoryTypeId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
        select max(CreationDate) from PostHistory ph2 where ph2.PostId = p.Id
    )
    where u.Reputation > 1000
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
TopTags as (
    select
        t.TagName,
        t.Count,
        row_number() over (order by t.Count desc) as rn
    from Tags t
    where t.Count > 1000
),
PostWithTagArray as (
    select
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><') as TagArray
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
PostsWithTopTags as (
    select
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        unnest(p.TagArray) as Tag
    from PostWithTagArray p
),
UserTopTagStats as (
    select
        p.OwnerUserId as UserId,
        p.Tag,
        count(*) as QuestionsCount,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews
    from PostsWithTopTags p
    join TopTags t on t.TagName = p.Tag
    group by p.OwnerUserId, p.Tag
),
UserTopTagRanked as (
    select
        ut.UserId,
        ut.Tag,
        ut.QuestionsCount,
        ut.AvgScore,
        ut.TotalViews,
        rank() over (partition by ut.UserId order by ut.QuestionsCount desc, ut.AvgScore desc) as TagRank
    from UserTopTagStats ut
),
UserTopTagsFiltered as (
    select *
    from UserTopTagRanked
    where TagRank <= 3
),
AnswersWithOwner as (
    select
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate
    from Posts a
    where a.PostTypeId = 2
),
QuestionsWithAcceptedAnswerScore as (
    select
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwnerId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
UserQuestionAnswerStats as (
    select
        q.QuestionOwnerId as UserId,
        count(distinct q.QuestionId) as TotalQuestions,
        count(distinct case when q.AcceptedAnswerId is not null then q.QuestionId end) as QuestionsWithAcceptedAnswer,
        avg(q.QuestionScore) as AvgQuestionScore,
        avg(coalesce(q.AcceptedAnswerScore, 0)) as AvgAcceptedAnswerScore
    from QuestionsWithAcceptedAnswerScore q
    group by q.QuestionOwnerId
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > cast('2024-10-01' as date) - interval '1 year' then 1 else 0 end) as CommentsLastYear
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserVoteStats as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.DistinctBadges,0) as DistinctBadges,
        coalesce(qas.TotalQuestions,0) as TotalQuestions,
        coalesce(qas.QuestionsWithAcceptedAnswer,0) as QuestionsWithAcceptedAnswer,
        coalesce(qas.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(qas.AvgAcceptedAnswerScore,0) as AvgAcceptedAnswerScore,
        coalesce(cs.TotalComments,0) as TotalComments,
        coalesce(cs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(cs.CommentsLastYear,0) as CommentsLastYear,
        coalesce(vs.UpVotesCast,0) as UpVotesCast,
        coalesce(vs.DownVotesCast,0) as DownVotesCast,
        coalesce(vs.FavoritesCast,0) as FavoritesCast
    from Users u
    left join UserBadgeCounts b on b.UserId = u.Id
    left join UserQuestionAnswerStats qas on qas.UserId = u.Id
    left join UserCommentStats cs on cs.UserId = u.Id
    left join UserVoteStats vs on vs.UserId = u.Id
    where u.Reputation > 5000
),
FinalResult as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        uas.DistinctBadges,
        uas.TotalQuestions,
        uas.QuestionsWithAcceptedAnswer,
        uas.AvgQuestionScore,
        uas.AvgAcceptedAnswerScore,
        uas.TotalComments,
        uas.AvgCommentLength,
        uas.CommentsLastYear,
        uas.UpVotesCast,
        uas.DownVotesCast,
        uas.FavoritesCast,
        string_agg(distinct ut.Tag, ', ') as TopTags
    from UserActivitySummary uas
    left join UserTopTagsFiltered ut on ut.UserId = uas.UserId
    group by 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        uas.DistinctBadges,
        uas.TotalQuestions,
        uas.QuestionsWithAcceptedAnswer,
        uas.AvgQuestionScore,
        uas.AvgAcceptedAnswerScore,
        uas.TotalComments,
        uas.AvgCommentLength,
        uas.CommentsLastYear,
        uas.UpVotesCast,
        uas.DownVotesCast,
        uas.FavoritesCast
)
select
    fr.*,
    case
        when fr.Reputation >= 50000 then 'Legend'
        when fr.Reputation >= 20000 then 'Expert'
        when fr.Reputation >= 10000 then 'Advanced'
        else 'Intermediate'
    end as UserLevel,
    case
        when fr.QuestionsWithAcceptedAnswer::float / nullif(fr.TotalQuestions,0) > 0.75 then 'High Acceptance'
        when fr.QuestionsWithAcceptedAnswer::float / nullif(fr.TotalQuestions,0) between 0.4 and 0.75 then 'Medium Acceptance'
        else 'Low Acceptance'
    end as AcceptanceCategory,
    (fr.UpVotesCast - fr.DownVotesCast) as NetVotesCast,
    (fr.GoldBadges * 3 + fr.SilverBadges * 2 + fr.BronzeBadges) as BadgeScore,
    length(fr.TopTags) as TopTagsNameLength
from FinalResult fr
where fr.TotalQuestions > 10
order by BadgeScore desc, fr.Reputation desc, fr.TotalComments desc
limit 50;