-- {"query": "1169.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1528} 
with RecursiveTaggedPosts as (
    select 
        p.Id, p.PostTypeId, p.Title, p.Tags, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
        1 as depth,
        array[substring(p.Tags from '<([^>]+)>')] as tag_array
    from 
        Posts p
    where 
        p.PostTypeId = 1
        and p.Tags is not null
        and p.Tags like '%<sql>%'
    
    union all
    
    select 
        p2.Id, p2.PostTypeId, p2.Title, p2.Tags, p2.OwnerUserId, p2.Score, p2.ViewCount, p2.AnswerCount,
        r.depth + 1,
        r.tag_array || substring(p2.Tags from '<([^>]+)>')
    from 
        Posts p2
        join RecursiveTaggedPosts r on p2.OwnerUserId = r.OwnerUserId
    where
        p2.PostTypeId = 1
        and p2.Tags is not null
        and p2.Tags like '%<sql>%'
        and r.depth < 3
),

UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        rank() over (order by count(distinct b.Id) desc) as BadgeRank
    from 
        Users u
        left join Badges b on u.Id = b.UserId
    group by
        u.Id, u.DisplayName
),

TopPostsWithVotes as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(v.Favorites, 0) as Favorites,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByType
    from 
        Posts p
        left join (
            select
                PostId,
                sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
                sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes,
                sum(case when VoteTypeId = 5 then 1 else 0 end) as Favorites
            from Votes
            group by PostId
        ) v on p.Id = v.PostId
    where 
        p.PostTypeId in (1, 2)
),

RecentCommentsWithAuthors as (
    select
        c.Id as CommentId,
        c.PostId,
        c.CreationDate,
        c.UserId,
        u.DisplayName as CommentAuthor,
        c.Score,
        length(c.Text) as TextLength,
        case 
            when u.Reputation > 10000 then 'HighReputation'
            when u.Reputation between 1000 and 10000 then 'MidReputation'
            else 'LowReputation' 
        end as ReputationTier
    from 
        Comments c
        left join Users u on c.UserId = u.Id
    where 
        c.CreationDate > now() - interval '30 days'
),

PostHistoryCloseReasonsCount as (
    select 
        ph.PostId, 
        crt.Name as CloseReason,
        count(*) as CloseVotesCount
    from 
        PostHistory ph
        join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where 
        ph.PostHistoryTypeId = 10 -- Post Closed 
        and crt.Id is not null
    group by ph.PostId, crt.Name
),

QuestionsWithDuplicatesAndAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        count(distinct pl2.RelatedPostId) filter (where pl1.LinkTypeId = 3) as DuplicateCount,
        count(distinct a.Id) as AnswerCount,
        max(a.Score) filter (where a.Id is not null) as MaxAnswerScore,
        avg(a.Score) filter (where a.Id is not null) as AvgAnswerScore,
        exists (
            select 1 
            from Posts a2 
            where a2.ParentId = q.Id 
            and a2.Score > 10
            limit 1
        ) as HasHighScoreAnswer
    from 
        Posts q
        left join PostLinks pl1 on q.Id = pl1.PostId
        left join PostLinks pl2 on pl1.Id = pl2.Id and pl2.LinkTypeId = 3
        left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where 
        q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate
)

select distinct
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.DuplicateCount,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    case when q.HasHighScoreAnswer then 'Yes' else 'No' end as HasHighScoreAnswer,
    close_reasons.CloseReason,
    close_reasons.CloseVotesCount,
    ubc.DisplayName as QuestionOwner,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    tp.UpVotes,
    tp.DownVotes,
    tp.Favorites,
    ARRAY_TO_STRING(rt.tag_array, ',') as TagsChain,
    c.Author_Reputation_Tier,
    c.CommentCount_30Days
from 
    QuestionsWithDuplicatesAndAnswers q
    left join PostHistoryCloseReasonsCount close_reasons on q.QuestionId = close_reasons.PostId
    left join Users u on u.Id = q.QuestionId
    left join UserBadgeCounts ubc on ubc.UserId = (select OwnerUserId from Posts where Id = q.QuestionId)
    left join TopPostsWithVotes tp on tp.Id = q.QuestionId
    left join RecursiveTaggedPosts rt on rt.Id = q.QuestionId
    left join (
        select
            c.PostId,
            max(rc.ReputationTier) as Author_Reputation_Tier,
            count(rc.CommentId) as CommentCount_30Days
        from
            RecentCommentsWithAuthors rc
            join Comments c on c.Id = rc.CommentId
        group by c.PostId
    ) c on c.PostId = q.QuestionId
where 
    (coalesce(q.DuplicateCount, 0) + coalesce(q.AnswerCount, 0)) > 5
    and q.CreationDate > now() - interval '365 days'
order by
    q.AnswerCount desc, q.DuplicateCount desc, q.CreationDate desc
limit 100;