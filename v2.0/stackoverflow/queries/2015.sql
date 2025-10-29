-- {"query": "2015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1751}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where (b.TagBased = false) or (b.TagBased is null)
),
TopBadgeUsers as (
    select
        UserId,
        DisplayName,
        BadgeName,
        BadgeClass
    from RecursiveUserBadges
    where BadgeRank <= 3
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        sum(case when p.AcceptedAnswerId is not null and p.PostTypeId = 1 then 1 else 0 end) as AcceptedAnswersCount
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
),
RecentActiveQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate >= (cast('2024-10-01' as date) - interval '180' day)
),
QuestionsWithComments as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        coalesce(c.CommentCount,0) as CommentCount,
        case when q.Tags is null then array[]::text[] else string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><') end as TagArray
    from Posts q
    left join (
        select
            PostId,
            count(*) as CommentCount
        from Comments
        group by PostId
    ) c on q.Id = c.PostId
    where q.PostTypeId = 1
),
DuplicatePostLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
UserAvgAnswerScore as (
    select
        p.OwnerUserId as UserId,
        avg(p.Score) as AvgAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.OwnerUserId
),
PostsWithCloseInfo as (
    select
        ph.PostId,
        ph.Comment as CloseReasonCode,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on cast(crt.Id as varchar) = ph.Comment
    where ph.PostHistoryTypeId = 10
),
UserClosingActivity as (
    select
        ph.UserId,
        count(distinct ph.PostId) as CloseCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.UserId is not null
    group by ph.UserId
),
RankedUserQuestions as (
    select
        q.Id,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        row_number() over (partition by q.OwnerUserId order by q.Score desc, q.ViewCount desc) as UserQuestionRank
    from Posts q
    where q.PostTypeId = 1
),
CombinedUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(ups.QuestionCount,0) as TotalQuestions,
        coalesce(ups.AnswerCount,0) as TotalAnswers,
        coalesce(ups.AvgQuestionScore,0) as AverageQuestionScore,
        coalesce(ups.AvgAnswerScore,0) as AverageAnswerScore,
        coalesce(ups.AcceptedAnswersCount,0) as AcceptedAnswersCount,
        coalesce(u.Reputation,0) as Reputation,
        coalesce(uca.CloseCount,0) as CloseVotesCast
    from Users u
    left join UserPostStats ups on u.Id = ups.UserId
    left join UserClosingActivity uca on u.Id = uca.UserId
),
StringAggTags as (
    select
        q.OwnerUserId as UserId,
        string_agg(t.TagName, ', ' order by t.Count desc) as PopularTags
    from Posts q
    join Tags t on t.TagName = any(string_to_array(substring(q.Tags, 2, length(q.Tags)-2),' ><'))
    where q.PostTypeId = 1 and q.Tags is not null
    group by q.OwnerUserId
),
FinalQuestionStats as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        coalesce(dpl.RelatedPostId, -1) as DuplicateOfPostId,
        coalesce(pc.CloseReasonName, 'Open') as CloseReason,
        rank() over (partition by q.OwnerUserId order by q.Score desc, q.ViewCount desc) as ScoreRank
    from Posts q
    left join DuplicatePostLinks dpl on q.Id = dpl.PostId
    left join PostsWithCloseInfo pc on q.Id = pc.PostId
    where q.PostTypeId = 1
)
select distinct
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.TotalQuestions,
    cu.TotalAnswers,
    cu.AverageQuestionScore,
    cu.AverageAnswerScore,
    cu.AcceptedAnswersCount,
    cu.CloseVotesCast,
    tb.BadgeName,
    tb.BadgeClass,
    sqs.Id as QuestionId,
    sqs.Title as QuestionTitle,
    sqs.CreationDate as QuestionCreationDate,
    sqs.Score as QuestionScore,
    sqs.ViewCount as QuestionViewCount,
    sqs.CloseReason,
    sqs.DuplicateOfPostId,
    st.PopularTags,
    row_number() over (partition by cu.UserId order by sqs.Score desc) as QuestionScoreOrdering,
    dense_rank() over (order by cu.Reputation desc, cu.TotalAnswers desc) as UserReputationRank,
    case 
        when cu.Reputation > 50000 then 'Expert'
        when cu.Reputation between 10000 and 50000 then 'Intermediate'
        when cu.Reputation < 10000 then 'Novice'
        else 'Unknown'
    end as UserLevel,
    concat_ws(' | ',
        concat('Q:', cu.TotalQuestions),
        concat('A:', cu.TotalAnswers),
        concat('Acc:', cu.AcceptedAnswersCount),
        concat('CloseV:', cu.CloseVotesCast)) as ActivitySummary,
    length(coalesce(sqs.Tags, '')) as TagsLength,
    (select count(*)
     from Comments c
     where c.PostId = sqs.Id
       and (lower(c.Text) like '%error%' or lower(c.Text) like '%fail%')) as CommentsWithErrorCount
from CombinedUserStats cu
left join TopBadgeUsers tb on cu.UserId = tb.UserId
left join FinalQuestionStats sqs on cu.UserId = sqs.OwnerUserId and sqs.ScoreRank <= 5
left join StringAggTags st on cu.UserId = st.UserId
where (cu.TotalQuestions > 0 or cu.TotalAnswers > 0)
  and (cu.CloseVotesCast > 0 or cu.AcceptedAnswersCount > 0)
order by UserReputationRank, cu.UserId, QuestionScoreOrdering
fetch first 100 rows only;