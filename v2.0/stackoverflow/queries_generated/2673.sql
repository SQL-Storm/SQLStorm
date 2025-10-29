-- {"query": "2673.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1174} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Id) as rn
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    union all
    select
        u2.Id,
        u2.DisplayName,
        0,
        0,
        0,
        ubc.rn + 1
    from
        Users u2
        join UserBadgeCounts ubc on ubc.rn + 1 = u2.Id
    where ubc.rn < 10
),
TopQuestions as (
    select 
        p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.Title,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as AnswerRank
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null
),
AnswerLinkRank as (
    select 
        l.PostId,
        l.RelatedPostId,
        l.LinkTypeId,
        rank() over (partition by l.PostId order by l.CreationDate desc) as LinkRank
    from PostLinks l
    where l.LinkTypeId in (1,3)
),
QuestionWithTopAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        a.CreationDate as AnswerCreationDate
    from TopQuestions q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.AnswerRank <= 3
),
VoteSummary as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
CommentInfo as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(substring(coalesce(c.Text, '') from 1 for 50), ' | ') as SampleComments
    from Comments c
    group by c.PostId
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    p.Id as QuestionId,
    p.Title,
    p.Score as QuestionScore,
    p.ViewCount,
    coalesce(vs.UpVotes, 0) as QuestionUpVotes,
    coalesce(vs.DownVotes, 0) as QuestionDownVotes,
    coalesce(vs.Favorites, 0) as QuestionFavorites,
    cinfo.CommentCount,
    cinfo.LastCommentDate,
    substring(cinfo.SampleComments from 1 for 200) as SampleCommentSnippets,
    ans.AnswerId,
    ans.AnswerScore,
    ans.AnswerCreationDate,
    ans_user.DisplayName as AnswerOwnerDisplayName,
    exists (
        select 1 from PostLinks pl where pl.PostId = ans.AnswerId and pl.LinkTypeId = 3
    ) as AnswerIsMarkedDuplicate,
    avg(p.Score) over (partition by p.OwnerUserId) as AvgUserQuestionScore,
    rank() over (order by u.Reputation desc) as UserReputationRank,
    case
        when u.Reputation > 10000 then 'High'
        when u.Reputation between 1000 and 10000 then 'Medium'
        else 'Low'
    end as ReputationCategory
from
    Users u
    inner join UserBadgeCounts ubc on ubc.UserId = u.Id and ubc.rn <= 20
    inner join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Score is not null
    left join VoteSummary vs on vs.PostId = p.Id
    left join CommentInfo cinfo on cinfo.PostId = p.Id
    left join QuestionWithTopAnswers ans on ans.QuestionId = p.Id
    left join Users ans_user on ans_user.Id = ans.AnswerOwnerId
where
    p.CreationDate >= current_date - interval '365 days'
    and (
        p.Score > (
            select avg(p2.Score) from Posts p2 where p2.OwnerUserId = p.OwnerUserId and p2.PostTypeId = 1
        )
        or exists (
            select 1 from Badges b where b.UserId = u.Id and b.Class = 1
        )
    )
order by
    UserReputationRank,
    p.Score desc
limit 100;