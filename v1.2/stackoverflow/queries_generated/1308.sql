-- {"query": "1308.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1602} 
with RecursiveRelatedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) as UserPostRank,
        1 as Depth,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only

    union all

    select
        pr.RelatedPostId as Id,
        q.PostTypeId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.CreationDate) as UserPostRank,
        pr.Depth + 1,
        Path || pr.RelatedPostId
    from RecursiveRelatedPosts pr
    join PostLinks pl on pl.PostId = pr.Id
    join Posts q on q.Id = pl.RelatedPostId
    join RecursiveRelatedPosts rr on rr.Id = pr.Id
    where pl.LinkTypeId = 1 -- Linked
      and pr.Depth < 3
      and not pr.Path @> array[pl.RelatedPostId]
),
UserBadgeAgg as (
    select 
        b.UserId,
        SUM(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        SUM(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        SUM(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        MAX(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostWithAnswersAndComments as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        c.CommentCount as AnswerCommentCount,
        u.DisplayName as QuestionOwner,
        ua.DisplayName as AnswerOwner,
        co.CommentCount as QuestionCommentCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2 
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = a.Id
    left join (
      select PostId, count(*) as CommentCount
      from Comments
      group by PostId
    ) co on co.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join Users ua on ua.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
FilteredVotes as (
    select 
        v.PostId, 
        count(*) filter (where v.VoteTypeId = 2) as UpVotes, 
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    where v.VoteTypeId in (2,3)
    group by v.PostId
),
AnswersRanked as (
    select
        a.*,
        ROW_NUMBER() over (partition by a.QuestionId order by a.AnswerScore desc, a.AnswerCommentCount desc) as AnswerRank,
        rank() over (partition by a.OwnerUserId order by a.AnswerScore desc) as UserAnswerRank
    from PostWithAnswersAndComments a
    where a.AnswerId is not null
),
QuestionsFiltered as (
    select 
        q.*, 
        f.UpVotes, 
        f.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ur.UserPostRank
    from RecursiveRelatedPosts rr
    join Posts q on q.Id = rr.Id and q.PostTypeId = 1
    left join FilteredVotes f on f.PostId = q.Id
    left join UserBadgeAgg ub on ub.UserId = q.OwnerUserId
    left join (
        select DISTINCT OwnerUserId, UserPostRank from RecursiveRelatedPosts
    ) ur on ur.OwnerUserId = q.OwnerUserId and ur.Id = q.Id
    where q.CreationDate > current_date - interval '365 days'
)
select
    qf.Id as QuestionId,
    coalesce(qf.Title, '[NO TITLE]') as Title,
    coalesce(qf.ViewCount, 0) as Views,
    coalesce(qf.Score, 0) as Score,
    coalesce(qf.UpVotes, 0) as UpVotes,
    coalesce(qf.DownVotes, 0) as DownVotes,
    u.DisplayName as OwnerDisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    qf.UserPostRank,
    -- Ratio and performance indices with complicated expressions:
    case when qf.DownVotes > 0 then round(cast(qf.UpVotes as numeric) / nullif(qf.DownVotes,0),3) else null end as UpDownRatio,
    round(100.0 * (qf.UpVotes + qf.DownVotes)::numeric / nullif(qf.ViewCount,1), 2) as VotePerViewPercent,
    -- Last activity window functions over answers
    sub.a_cnt,
    sub.avg_answer_score,
    sub.top_answer_user,
    -- Using correlated subquery to find the top answer body snippet, with NULL logic and string handling
    (select substring(coalesce(p.Body,'') from 1 for 100)||case when length(coalesce(p.Body,'')) > 100 then '...' else '' end
     from Posts p where p.Id = qf.AcceptedAnswerId) as AcceptedAnswerSnippet
from QuestionsFiltered qf
left join Users u on u.Id = qf.OwnerUserId
left join UserBadgeAgg ub on ub.UserId = qf.OwnerUserId
left join lateral (
    select 
      count(*) as a_cnt,
      round(avg(a.AnswerScore)::numeric, 2) as avg_answer_score,
      max(uans.DisplayName) as top_answer_user
    from Posts a
    left join Users uans on uans.Id = a.OwnerUserId
    where a.ParentId = qf.Id and a.PostTypeId = 2
) sub on true
where qf.Score > (
    select avg(Score)::int from Posts where PostTypeId=1
)
union
select
    u.Id,
    u.DisplayName,
    null::int as Views,
    null::int as Score,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    null::int as GoldBadges,
    null::int as SilverBadges,
    null::int as BronzeBadges,
    null::int as UserPostRank,
    null::numeric as UpDownRatio,
    null::numeric as VotePerViewPercent,
    null::int as a_cnt,
    null::numeric as avg_answer_score,
    null::varchar(40) as top_answer_user,
    null::varchar(103) as AcceptedAnswerSnippet
from Users u
where u.Reputation > (
    select max(Reputation)/2 from Users
)
order by Score desc NULLS LAST, Views desc NULLS LAST
limit 100;